//
//  Database.swift
//  simple-intelligence
//
//  Created by Wayne Carter on 5/18/24.
//

import UIKit
import CouchbaseLiteSwift
import Combine

class Database {
    static let shared = Database()
    
    private var database: CouchbaseLiteSwift.Database!
    private var collection: CouchbaseLiteSwift.Collection!
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        setupDatabase()
        endpoint = Settings.shared.endpoint
        
        // When the demo is enabled/disabled, update the database and sync
        Settings.shared.$isDemoEnabled
            .dropFirst()
            .sink { [weak self] isDemoEnabled in
                self?.stopSync()
                self?.setupDatabase(isDemoEnabled: isDemoEnabled)
                self?.startSync()
            }.store(in: &cancellables)
        
        // When the endpoint settings change, update the sync endpoint
        Settings.shared.$endpoint
            .dropFirst()
            .sink { [weak self] newEndpoint in
                self?.endpoint = newEndpoint
            }.store(in: &cancellables)
    }
    
    private func setupDatabase(isDemoEnabled: Bool = Settings.shared.isDemoEnabled) {
        var database: CouchbaseLiteSwift.Database
        var collection: CouchbaseLiteSwift.Collection
        
        if isDemoEnabled {
            // Setup the demo database
            database = try! CouchbaseLiteSwift.Database(name: "demo")
            collection = try! database.defaultCollection()
            
            // If the database isn't up to date with the latest demo
            // data then delete and recreate it
            var isLatest = false
            if let doc = try? collection.document(id: "product:1"),
               let imageData = doc["image"].blob?.content,
               let image = UIImage(data: imageData),
               image.size.width == 1206
            {
                isLatest = true
            }
            if !isLatest {
                try! database.delete()
                database = try! CouchbaseLiteSwift.Database(name: "demo")
                collection = try! database.defaultCollection()
            }
            
            // If the database is empty, initialize it with the demo data.
            if collection.count == 0  {
                loadDemoData(in: collection)
            }
        } else {
            database = try! CouchbaseLiteSwift.Database(name: "intelligence")
            collection = try! database.defaultCollection()
        }
        
        // Initialize the value index on the "name" field for fast sorting.
        let nameIndex = ValueIndexConfiguration(["name"])
        try! collection.createIndex(withName: "NameIndex", config: nameIndex)
        
        // Initialize the value index on the "barcode" field for fast searching.
        let barcodeIndex = ValueIndexConfiguration(["barcode"])
        try! collection.createIndex(withName: "BarcodeIndex", config: barcodeIndex)
        
        // Initialize the vector index on the "embedding" field for image search.
        var vectorIndex = VectorIndexConfiguration(expression: "embedding", dimensions: 768, centroids: 2)
        vectorIndex.metric = .cosine
        try! collection.createIndex(withName: "EmbeddingVectorIndex", config: vectorIndex)
        
        // Initialize the full-text search index on the "name" and "category" fields.
        let ftsIndex = FullTextIndexConfiguration(["name", "category"])
        try! collection.createIndex(withName: "NameAndCategoryFullTextIndex", config: ftsIndex)
        
        self.database = database
        self.collection = collection
    }
    
    deinit {
        cancellables.removeAll()
        stopSync()
    }
    
    // MARK: - Search
    
    func search(image: UIImage) -> [Record] {
        let dispatchGroup = DispatchGroup()
        var barcodeSearchResults: [Product]?
        var faceSearchResults: [Record]?
        var embeddingSearchResults: [Record]?
        
        // Perform barcode search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            if let barcode = AI.shared.barcode(from: image), let product = self.search(barcode: barcode) {
                barcodeSearchResults = [product]
            }
        }
        
        // Perform face search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            
            if let embedding = AI.shared.embedding(for: image, attention: .faces) {
                let searchResults = self.search(vector: embedding, maxDistance: 0.1)
                faceSearchResults = searchResults
            }
        }
        
        // Perform embedding search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            
            let embeddings = AI.shared.embeddings(for: image, attention: .zoom(factors: [1, 2]))
            for embedding in embeddings {
                let searchResults = self.search(vector: embedding)
                guard searchResults.isEmpty else {
                    embeddingSearchResults = searchResults
                    break
                }
            }
        }
        
        // Wait for parallel searches to complete
        dispatchGroup.wait()
        
        // Return barcode results if available, then face results, otherwise return embedding results
        let searchResults = barcodeSearchResults ?? faceSearchResults ?? embeddingSearchResults ?? []
        return searchResults
    }
    
    private func search(vector: [NSNumber], maxDistance: Float = 0.25) -> [Record] {
        // SQL
        let sql = """
            SELECT type, name, price, location, image, VECTOR_DISTANCE(EmbeddingVectorIndex) AS distance
            FROM _
            WHERE (type = "product" OR type = "booking")
                AND VECTOR_MATCH(EmbeddingVectorIndex, $embedding, 10)
                AND VECTOR_DISTANCE(EmbeddingVectorIndex) <= \(maxDistance)
            ORDER BY VECTOR_DISTANCE(EmbeddingVectorIndex), name
        """
        
        do {
            // Create the query.
            let query = try collection.database.createQuery(sql)
            query.parameters = Parameters()
                .setArray(MutableArrayObject(data: vector), forName: "embedding")
            
            // Execute the query and get the results.
            let results = try query.execute()
            
            // Enumerate through the query results.
            var records = [Record]()
            var distances = [Double]()
            for result in results {
                if let type = result["type"].string,
                   let imageData = result["image"].blob?.content,
                   let imageDigest = result["image"].blob?.digest,
                   let image = UIImage(data: imageData)
                {
                    let record: Record
                    if type == "product",
                       let name = result["name"].string,
                       let price = result["price"].number,
                       let location = result["location"].string
                    {
                        record = Product(name: name, price: price.doubleValue, location: location, image: image, imageDigest: imageDigest)
                    } else {
                        record = Booking(image: image, imageDigest: imageDigest)
                    }
                    records.append(record)
                    
                    let distance = result["distance"].number?.doubleValue ?? .greatestFiniteMagnitude
                    distances.append(distance)
                }
            }
            
            // Post process and filter any matches that are too far away from the closest match.
            var filteredRecords = [Record]()
            let minimumDistance: Double = {
                let minimumDistance = distances.min { a, b in a < b }
                return minimumDistance ?? .greatestFiniteMagnitude
            }()
            for (index, distance) in distances.enumerated() {
                if distance <= minimumDistance * 1.40 {
                    let record = records[index]
                    filteredRecords.append(record)
                }
            }
            
            return filteredRecords
        } catch {
            print("Database.search(vector:): \(error.localizedDescription)")
            return []
        }
    }
    
    private func search(barcode: String) -> Product? {
        // SQL
        let sql = """
            SELECT name, price, location, image
            FROM _
            WHERE type = "product"
                AND barcode = $barcode
            LIMIT 1
        """
        
        do {
            // Create the query
            let query = try collection.database.createQuery(sql)
            query.parameters = Parameters()
                .setString(barcode, forName: "barcode")
            
            // Execute the query and get the results
            let results = try query.execute()
            
            // Return the first search result
            if let result = results.next(),
               let name = result["name"].string,
               let price = result["price"].number,
               let location = result["location"].string,
               let imageData = result["image"].blob?.content,
               let imageDigest = result["image"].blob?.digest,
               let image = UIImage(data: imageData)
            {
                let product = Product(name: name, price: price.doubleValue, location: location, image: image, imageDigest: imageDigest)
                return product
            }
        } catch {
            print("Database.search(barcode:): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    func search(string: String) -> [Product] {
        var searchString = string.trimmingCharacters(in: .whitespaces)
        if !searchString.hasSuffix("*") {
            searchString = searchString.appending("*")
        }
        
        // SQL
        let sql = """
            SELECT name, price, location, image
            FROM _
            WHERE type = "product"
                AND MATCH(NameAndCategoryFullTextIndex, $search)
            ORDER BY RANK(NameAndCategoryFullTextIndex), name
        """
        
        do {
            // Create the query.
            let query = try collection.database.createQuery(sql)
            query.parameters = Parameters()
                .setString(searchString, forName: "search")
            
            // Execute the query and get the results.
            let results = try query.execute()
            
            // Enumerate through the query results.
            var products = [Product]()
            for result in results {
                if let name = result["name"].string,
                   let price = result["price"].number,
                   let location = result["location"].string,
                   let imageData = result["image"].blob?.content,
                   let imageDigest = result["image"].blob?.digest,
                   let image = UIImage(data: imageData)
                {
                    let product = Product(name: name, price: price.doubleValue, location: location, image: image, imageDigest: imageDigest)
                    products.append(product)
                }
            }
            
            return products
        } catch {
            // If the query fails, return an empty result. This is expected when the user is
            // typing an FTS expression but they haven't completed typing so the query is
            // invalid. e.g. "(blue OR"
            return []
        }
    }
    
    // MARK: - Cart
    
    var cartTotal: Double {
        do {
            let cart = try collection.document(id: "cart")
            let total = cart?["total"].double ?? .zero
            return total
        } catch {
            print("Database.cartTotal: \(error.localizedDescription)")
            return .zero
        }
    }
    
    func addToCart(product: Product) {
        do {
            guard let name = product.name, let price = product.price else { return }
            
            // Get or create the cart document.
            let cart = try collection.document(id: "cart")?.toMutable() ?? MutableDocument(id: "cart")
            
            // Create the item dicionary
            let item = MutableDictionaryObject(data: [
                "name": name,
                "price": price
            ])
            
            // Add the item to the cart
            let items = cart["items"].array ?? MutableArrayObject()
            items.addDictionary(item)
            cart["items"].array = items
            
            // Update the cart total
            var total = Double()
            for item in items {
                if let item = item as? MutableDictionaryObject {
                    total += item["price"].double
                }
            }
            cart["total"].double = total
            
            // Save the cart
            try collection.save(document: cart)
        } catch {
            print("Database.addToCart: \(error.localizedDescription)")
        }
    }
    
    func clearCart() {
        do {
            // If the cart doc exists, delete it.
            if let cart = try collection.document(id: "cart") {
                try collection.delete(document: cart)
            }
        } catch {
            print("Database.clearCart: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Records
    
    class Product: Record {
        let name: String?
        let price: Double?
        let location: String?
        
        fileprivate init(name: String, price: Double, location: String, image: UIImage, imageDigest: String) {
            self.name = name
            self.price = price
            self.location = location
            super.init(title: name, subtitle: String(format: "$%.02f", price), details: location, image: image, imageDigest: imageDigest)
        }
    }
    
    class Booking: Record {
        
    }
    
    class Record: Equatable {
        let title: String?
        let subtitle: String?
        let details: String?
        let image: UIImage
        let imageDigest: String
        
        fileprivate init(image: UIImage, imageDigest: String) {
            self.title = nil
            self.subtitle = nil
            self.details = nil
            self.image = image
            self.imageDigest = imageDigest
        }
        
        fileprivate init(title: String, subtitle: String, details: String, image: UIImage, imageDigest: String) {
            self.title = title
            self.subtitle = subtitle
            self.details = details
            self.image = image
            self.imageDigest = imageDigest
        }
        
        static func == (lhs: Record, rhs: Record) -> Bool {
            return lhs.title == rhs.title
            && lhs.subtitle == rhs.subtitle
            && lhs.details == rhs.details
            && lhs.imageDigest == rhs.imageDigest
        }
    }
    
    // MARK: - Sync
    
    private var replicator: Replicator?
    private var backgroundSyncTask: UIBackgroundTaskIdentifier?
    
    private var endpoint: Settings.Endpoint? {
        didSet {
            startSync()
        }
    }
    
    private func startSync() {
        stopSync()
        
        // Create and start the replicator
        replicator = createReplicator()
        replicator?.start()
    }
    
    private func stopSync() {
        if let replicator = replicator {
            // Stop and nullify the replicator
            replicator.stop()
            self.replicator = nil
        }
    }
    
    private func createReplicator() -> Replicator? {
        guard let endpoint = endpoint else { return nil }
        guard endpoint.url.scheme == "ws" || endpoint.url.scheme == "wss" else { return nil }
        
        // Set up the target endpoint.
        let target = URLEndpoint(url: endpoint.url)
        var config = ReplicatorConfiguration(target: target)
        config.addCollection(collection)
        config.replicatorType = .pull
        config.continuous = true
        
        // If the endpoint has a username and password then use then assign a basic
        // authenticator using the credentials.
        if let username = endpoint.username, let password = endpoint.password {
            config.authenticator = BasicAuthenticator(username: username, password: password)
        }

        // Create and return the replicator.
        let endpointReplicator = Replicator(config: config)
        return endpointReplicator
    }
    
    // MARK: - Demo
    
    private func loadDemoData(in collection: CouchbaseLiteSwift.Collection) {
        let productsData: [[String: Any]] = [
            // Food
            ["id": "product:1", "type": "product", "name": "Lettuce", "image": "demo-images/lettuce", "category": "Food", "price": 1.49, "location": "Aisle 1"],
            ["id": "product:2", "type": "product", "name": "Hot Pepper", "image": "demo-images/hot-pepper", "category": "Food", "price": 0.99, "location": "Aisle 1"],
            ["id": "product:3", "type": "product", "name": "Grapes", "image": "demo-images/grapes", "category": "Food", "price": 2.49, "location": "Aisle 1"],
            ["id": "product:4", "type": "product", "name": "Doughnut", "image": "demo-images/doughnut", "category": "Food", "price": 1.99, "location": "Aisle 1"],
            // Home
            ["id": "product:5", "type": "product", "name": "Bolt", "image": "demo-images/bolt", "category": "Home", "price": 0.50, "location": "Aisle 2"],
            ["id": "product:6", "type": "product", "name": "Hammer", "image": "demo-images/hammer", "category": "Home", "price": 15.99, "location": "Aisle 2", "barcode": "000000000044"],
            ["id": "product:7", "type": "product", "name": "Wrench", "image": "demo-images/wrench", "category": "Home", "price": 14.99, "location": "Aisle 2"],
            // Office
            ["id": "product:8", "type": "product", "name": "Scissors", "image": "demo-images/scissors", "category": "Office", "price": 12.99, "location": "Aisle 3", "barcode": "000000000046"],
            ["id": "product:9", "type": "product", "name": "Paper Clip", "image": "demo-images/paperclip", "category": "Office", "price": 2.99, "location": "Aisle 3"],
            ["id": "product:10", "type": "product", "name": "Push Pin", "image": "demo-images/pushpin", "category": "Office", "price": 3.49, "location": "Aisle 3"]
        ]
        
        // Write product data to database.
        for (_, var productData) in productsData.enumerated() {
            // Create a document
            let id = productData.removeValue(forKey: "id") as? String
            let document = MutableDocument(id: id, data: productData)
            
            // If the data has an image property with a string value, convert it to an image
            // from the app assets
            if let imageName = document["image"].string,
               let image = UIImage(named: "\(imageName)"),
               let pngData = image.pngData()
            {
                DispatchQueue.global().async(qos: .userInitiated) {
                    if let embedding = AI.shared.embedding(for: image, attention: .none) {
                        document["image"].blob = Blob(contentType: "image/png", data: pngData)
                        document["embedding"].array = MutableArrayObject(data: embedding)
                        try! collection.save(document: document)
                    }
                }
            }
            try! collection.save(document: document)
        }
        
        let bookingsData: [[String: Any]] = [
            // Airline
            ["id": "booking:1", "type": "booking", "face": "demo-images/airline-customer", "image": "demo-images/airline-booking"],
            // Hotel
            ["id": "booking:2", "type": "booking", "face": "demo-images/hotel-customer", "image": "demo-images/hotel-booking"]
        ]
        
        // Write booking data to database.
        for (_, var bookingData) in bookingsData.enumerated() {
            // Create a document
            let id = bookingData.removeValue(forKey: "id") as? String
            let document = MutableDocument(id: id, data: bookingData)
            
            // If the data has an image property with a string value, convert it to an image
            // from the app assets
            if let imageName = document["image"].string,
               let image = UIImage(named: imageName),
               let pngData = image.pngData()
            {
                document["image"].blob = Blob(contentType: "image/png", data: pngData)
            }
            try! collection.save(document: document)
            
            // If the data has a face property, load the image from the assets, generate an
            // embedding, and update the document
            if let imageName = document["face"].string,
               let image = UIImage(named: imageName)
            {
                DispatchQueue.global().async(qos: .userInitiated) {
                    if let embedding = AI.shared.embedding(for: image, attention: .faces) {
                        document.removeValue(forKey: "face")
                        document["embedding"].array = MutableArrayObject(data: embedding)
                        try! collection.save(document: document)
                    }
                }
            }
        }
    }
    
    // MARK: - Testing
    
    private func test() {
        // Full text search
        print("Full text search: \(search(string: "Green"))")
        print()
        
        // Vector search
        if let embedding = AI.shared.embedding(for: UIImage(named: "demo-images/hot-pepper")!) {
            print("Full text search: \(self.search(vector: embedding))")
            print()
        }
        
        // Add to cart and cart total
        print("Cart total before adding product: \(cartTotal)")
        let image = UIImage(named: "demo-images/hot-pepper")!
        let imageData = image.pngData()!
        let blob = Blob(contentType: "image/png", data: imageData)
        let imageDigest = blob.digest!
        addToCart(product: Product(name: "Hot Pepper", price: 099, location: "Aisle 1", image: image, imageDigest: imageDigest))
        print("Cart total after adding product: \(cartTotal)")
        print()
        
        // Clear cart
        clearCart()
        print("Cart total after clearing cart: \(cartTotal)")
    }
}
