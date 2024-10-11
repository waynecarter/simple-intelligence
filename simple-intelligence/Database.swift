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
        startSync()
        
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
        
        // Enable the vector search extension
        try! CouchbaseLiteSwift.Extension.enableVectorSearch()
        
        if isDemoEnabled {
            // Setup the demo database
            database = try! CouchbaseLiteSwift.Database(name: "demo")
            collection = try! database.defaultCollection()
            
            // If the database isn't up to date with the latest demo
            // data then delete and recreate it
            var isLatest = false
            if let _ = try? collection.index(withName: "FaceVectorIndex") {
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
        
        // Initialize the vector index on the "image" field for image search.
        var imageVectorIndex = VectorIndexConfiguration(expression: "image", dimensions: 768, centroids: 2)
        imageVectorIndex.metric = .cosine
        imageVectorIndex.isLazy = true
        try! collection.createIndex(withName: "ImageVectorIndex", config: imageVectorIndex)
        
        // Initialize the vector index on the "face" field for image search.
        var faceVectorIndex = VectorIndexConfiguration(expression: "face", dimensions: 768, centroids: 2)
        faceVectorIndex.metric = .cosine
        faceVectorIndex.isLazy = true
        try! collection.createIndex(withName: "FaceVectorIndex", config: faceVectorIndex)
        
        // Initialize the full-text search index on the "name" and "category" fields.
        let ftsIndex = FullTextIndexConfiguration(["name", "category"])
        try! collection.createIndex(withName: "NameAndCategoryFullTextIndex", config: ftsIndex)
        
        setupAsyncIndexing(for: collection)
        
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
        var bookingSearchResults: [Booking]?
        var productSearchResults: [Product]?
        
        // Perform barcode search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            if let barcode = AI.shared.barcode(from: image), let product = self.searchProducts(barcode: barcode) {
                barcodeSearchResults = [product]
            }
        }
        
        // Perform booking search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            
            if let embedding = AI.shared.embedding(for: image, attention: .faces),
               let booking = self.searchBookings(vector: embedding)
            {
                bookingSearchResults = [booking]
            }
        }
        
        // Perform product search in parallel
        dispatchGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            defer { dispatchGroup.leave() }
            
            let embeddings = AI.shared.embeddings(for: image, attention: .zoom(factors: [1, 2]))
            for embedding in embeddings {
                productSearchResults = self.searchProducts(vector: embedding)
            }
        }
        
        // Wait for parallel the searches to complete
        dispatchGroup.wait()
        
        // Return barcode results if available, then booking results, otherwise return product results
        if let barcodeSearchResults {
            return barcodeSearchResults
        } else if let bookingSearchResults {
            return bookingSearchResults
        } else if let productSearchResults {
            return productSearchResults
        } else {
            return []
        }
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
    
    private func searchProducts(vector: [Float]) -> [Product] {
        // SQL
        let sql = """
            SELECT name, price, location, image, APPROX_VECTOR_DISTANCE(image, $embedding) AS distance
            FROM _
            WHERE type = "product"
              AND distance BETWEEN 0 AND 0.25
            ORDER BY distance, name
            LIMIT 10
        """
        
        do {
            // Create the query.
            let query = try collection.database.createQuery(sql)
            query.parameters = Parameters()
                .setArray(MutableArrayObject(data: vector), forName: "embedding")
            
            // Execute the query and enumerate through the query results.
            var products = [Product]()
            var distances = [Double]()
            for result in try query.execute() {
                if let imageBlob = result["image"].blob,
                   let imageData = imageBlob.content,
                   let imageDigest = imageBlob.digest,
                   let image = UIImage(data: imageData)
                {
                    if let name = result["name"].string,
                       let price = result["price"].number,
                       let location = result["location"].string
                    {
                        let product = Product(name: name, price: price.doubleValue, location: location, image: image, imageDigest: imageDigest)
                        products.append(product)
                        
                        let distance = result["distance"].number?.doubleValue ?? .greatestFiniteMagnitude
                        distances.append(distance)
                    }
                }
            }
            
            // Post process and filter any matches that are too far away from the closest match.
            var filteredProducts = [Product]()
            let minimumDistance: Double = {
                let minimumDistance = distances.min { a, b in a < b }
                return minimumDistance ?? .greatestFiniteMagnitude
            }()
            for (index, distance) in distances.enumerated() {
                if distance <= minimumDistance * 1.40 {
                    let product = products[index]
                    filteredProducts.append(product)
                }
            }
            
            return filteredProducts
        } catch {
            print("Database.searchProducts(vector:): \(error.localizedDescription)")
            return []
        }
    }
    
    private func searchProducts(barcode: String) -> Product? {
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
            
            // Execute the query and return the first search result
            if let result = try query.execute().next(),
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
            print("Database.searchProducts(barcode:): \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func searchBookings(vector: [Float]) -> Booking? {
        // SQL
        let sql = """
            SELECT image, APPROX_VECTOR_DISTANCE(face, $embedding) AS distance
            FROM _
            WHERE type = "booking"
              AND distance BETWEEN 0 AND 0.1
            ORDER BY distance
            LIMIT 1
        """
        
        do {
            // Create the query.
            let query = try collection.database.createQuery(sql)
            query.parameters = Parameters()
                .setArray(MutableArrayObject(data: vector), forName: "embedding")
            
            // Execute the query and and enumerate through the query results.
            for result in try query.execute() {
                if let imageBlob = result["image"].blob,
                   let imageData = imageBlob.content,
                   let imageDigest = imageBlob.digest,
                   let image = UIImage(data: imageData)
                {
                    return Booking(image: image, imageDigest: imageDigest)
                }
            }
            
            return nil
        } catch {
            print("Database.searchBookings(faceVector:): \(error.localizedDescription)")
            return nil
        }
    }
    
    // MARK: - Async Indexing
    
    private let asyncIndexQueue = DispatchQueue(label: "AsyncIndexUpdateQueue")
    
    private func setupAsyncIndexing(for collection: CouchbaseLiteSwift.Collection) {
        // Immediately update the async indexes
        asyncIndexQueue.async { [weak self] in
            do {
                try self?.updateAsyncIndexes(for: collection)
            } catch {
                print("Error updating async indexes: \(error)")
            }
        }
        
        // When the collection changes, update the async indexes
        collection.addChangeListener { [weak self] _ in
            self?.asyncIndexQueue.async {
                do {
                    try self?.updateAsyncIndexes(for: collection)
                } catch {
                    print("Error updating async indexes: \(error)")
                }
            }
        }
    }
    
    private func updateAsyncIndexes(for collection: CouchbaseLiteSwift.Collection) throws {
        // Upate the images vector index
        let imageVectorIndex = try collection.index(withName: "ImageVectorIndex")!
        while (true) {
            guard let indexUpdater = try imageVectorIndex.beginUpdate(limit: 10) else {
                break // Up to date
            }
            
            // Generate the new embedding and set it in the index
            for i in 0..<indexUpdater.count {
                if let data = indexUpdater.blob(at: i)?.content, let image = UIImage(data: data) {
                    let embedding = AI.shared.embedding(for: image, attention: .none)
                    try indexUpdater.setVector(embedding, at: i)
                }
            }
            try indexUpdater.finish()
        }
        
        // Upate the faces vector index
        let faceVectorIndex = try collection.index(withName: "FaceVectorIndex")!
        while (true) {
            guard let indexUpdater = try faceVectorIndex.beginUpdate(limit: 10) else {
                break // Up to date
            }
            
            // Generate the new embedding and set it in the index
            for i in 0..<indexUpdater.count {
                if let data = indexUpdater.blob(at: i)?.content, let image = UIImage(data: data) {
                    let embedding = AI.shared.embedding(for: image, attention: .faces)
                    try indexUpdater.setVector(embedding, at: i)
                }
            }
            try indexUpdater.finish()
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
        let demoData: [[String: Any]] = [
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
            ["id": "product:10", "type": "product", "name": "Push Pin", "image": "demo-images/pushpin", "category": "Office", "price": 3.49, "location": "Aisle 3"],
            // Airline
            ["id": "booking:1", "type": "booking", "face": "demo-images/airline-customer", "image": "demo-images/airline-booking"],
            // Hotel
            ["id": "booking:2", "type": "booking", "face": "demo-images/hotel-customer", "image": "demo-images/hotel-booking"]
        ]
        
        // Write demo data to database.
        for (_, var demoItemData) in demoData.enumerated() {
            // Create a document
            let id = demoItemData.removeValue(forKey: "id") as? String
            let document = MutableDocument(id: id, data: demoItemData)
            
            // If the data has an image property with a string value, convert it to an image
            // from the app assets
            if let imageName = document["image"].string,
               let image = UIImage(named: "\(imageName)"),
               let pngData = image.pngData()
            {
                document["image"].blob = Blob(contentType: "image/png", data: pngData)
            }
            
            // If the data has an face property with a string value, convert it to an image
            // from the app assets
            if let imageName = document["face"].string,
               let image = UIImage(named: imageName),
               let pngData = image.pngData()
            {
                document["face"].blob = Blob(contentType: "image/png", data: pngData)
            }
            
            try! collection.save(document: document)
        }
    }
    
    // MARK: - Testing
    
    private func test() {
        // Full text search
        print("Full text search: \(search(string: "Green"))")
        print()
        
        // Vector search
        if let embedding = AI.shared.embedding(for: UIImage(named: "demo-images/hot-pepper")!) {
            print("Vector search: \(self.searchProducts(vector: embedding))")
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
