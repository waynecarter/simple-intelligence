//
//  Database.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/18/24.
//

import UIKit
import CouchbaseLiteSwift
import Combine

class Database {
    static let shared = Database()
    
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    
    private var cancellables = Set<AnyCancellable>()
    
    private init() {
        database = try! CouchbaseLiteSwift.Database(name: "pos")
        collection = try! database.defaultCollection()
        
        // If the database is empty, initialize it with the demo data.
        if collection.count == 0  {
            loadDemoData(in: collection)
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
        try! collection.createIndex(withName: "ImageVectorIndex", config: vectorIndex)
        
        // Initialize the full-text search index on the "name" and "category" fields.
        let ftsIndex = FullTextIndexConfiguration(["name", "category"])
        try! collection.createIndex(withName: "NameAndCategoryFullTextIndex", config: ftsIndex)
        
        startAppService()
    }
    
    deinit {
        cancellables.removeAll()
        stopAppService()
    }
    
    // MARK: - Search
    
    func search(image: UIImage) -> [Product] {
        // Search with barcode
        if let barcode = AI.shared.barcode(from: image), let product = search(barcode: barcode) {
            return [product]
        }
        
        // Search with embedding
        if let embedding = AI.shared.embedding(for: image) {
            let products = search(vector: embedding)
            return products
        }
        
        return []
    }
    
    private func search(vector: [NSNumber]) -> [Product] {
        // SQL
        let sql = """
            SELECT name, price, location, image, VECTOR_DISTANCE(ImageVectorIndex) AS distance
            FROM _
            WHERE type = "product"
                AND VECTOR_MATCH(ImageVectorIndex, $embedding, 10)
                AND VECTOR_DISTANCE(ImageVectorIndex) < 0.25
            ORDER BY VECTOR_DISTANCE(ImageVectorIndex), name
        """
        
        // Set query parameters
        let parameters = Parameters()
        parameters.setArray(MutableArrayObject(data: vector), forName: "embedding")
        
        do {
            // Create the query.
            let query = try database.createQuery(sql)
            query.parameters = parameters
            
            // Execute the query and get the results.
            let results = try query.execute()
            
            // Enumerate through the query results.
            var products = [Product]()
            var distances = [Double]()
            for result in results {
                if let name = result["name"].string,
                   let price = result["price"].number,
                   let location = result["location"].string,
                   let imageData = result["image"].blob?.content,
                   let image = UIImage(data: imageData)
                {
                    let product = Product(name: name, price: price.doubleValue, location: location, image: image)
                    products.append(product)
                    
                    let distance = result["distance"].number?.doubleValue ?? .greatestFiniteMagnitude
                    distances.append(distance)
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
            print("Database.search(vector:): \(error.localizedDescription)")
            return [Product]()
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
        
        // Set query parameters
        let parameters = Parameters()
        parameters.setString(barcode, forName: "barcode")
        
        do {
            // Create the query
            let query = try database.createQuery(sql)
            query.parameters = parameters
            
            // Execute the query and get the results
            let results = try query.execute()
            
            // Return the first search result
            if let result = results.next(),
               let name = result["name"].string,
               let price = result["price"].number,
               let location = result["location"].string,
               let imageData = result["image"].blob?.content,
               let image = UIImage(data: imageData)
            {
                let product = Product(name: name, price: price.doubleValue, location: location, image: image)
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
        
        // Set query parameters
        let parameters = Parameters()
        parameters.setString(searchString, forName: "search")
        
        do {
            // Create the query.
            let query = try database.createQuery(sql)
            query.parameters = parameters
            
            // Execute the query and get the results.
            let results = try query.execute()
            
            // Enumerate through the query results.
            var products = [Product]()
            for result in results {
                if let name = result["name"].string,
                   let price = result["price"].number,
                   let location = result["location"].string,
                   let imageData = result["image"].blob?.content,
                   let image = UIImage(data: imageData)
                {
                    let product = Product(name: name, price: price.doubleValue, location: location, image: image)
                    products.append(product)
                }
            }
            
            return products
        } catch {
            // If the query fails, return an empty result. This is expected when the user is
            // typing an FTS expression but they haven't completed typing so the query is
            // invalid. e.g. "(blue OR"
            return [Product]()
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
            // Get or create the cart document.
            let cart = try collection.document(id: "cart")?.toMutable() ?? MutableDocument(id: "cart")
            
            // Create the item dicionary
            let item = MutableDictionaryObject(data: [
                "name": product.name,
                "price": product.price
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
    
    // MARK: - Product
    
    struct Product: Equatable {
        let name: String
        let price: Double
        let location: String
        let image: UIImage
        
        fileprivate init(name: String, price: Double, location: String, image: UIImage) {
            self.name = name
            self.price = price
            self.location = location
            self.image = image
        }
        
        static func == (lhs: Product, rhs: Product) -> Bool {
            return lhs.name == rhs.name
            && lhs.location == rhs.location
            && lhs.price == rhs.price
        }
    }
    
    // MARK: - App Service
    
    private var appService: AppService!
    
    private func startAppService() {
        // Create the app service with the configured endpoint
        appService = AppService(database: database, collections: [collection], endpoint: Settings.shared.endpoint)
        
        // When the endpoint settings change, update the app service
        Settings.shared.$endpoint
            .sink { [weak self] newEndpoint in
                self?.appService.endpoint = newEndpoint
            }.store(in: &cancellables)
        
        // Start the app service and start syncing with the configured endpoint
        appService.start()
    }
    
    private func stopAppService() {
        appService.stop()
    }
    
    // MARK: - Util
    
    private func loadDemoData(in collection: CouchbaseLiteSwift.Collection) {
        let productsData: [[String: Any]] = [
            // Vegetables
            ["id": "product:1", "type": "product", "barcode": "000000000001", "name": "Hot Pepper", "emoji": "🌶️", "color": "red", "category": "Produce", "price": 0.99, "location": "Aisle 1"],
            ["id": "product:2", "type": "product", "barcode": "000000000002", "name": "Carrot", "emoji": "🥕", "color": "orange", "category": "Produce", "price": 0.79, "location": "Aisle 1"],
            ["id": "product:3", "type": "product", "barcode": "000000000003", "name": "Lettuce", "emoji": "🥬", "color": "green", "category": "Produce", "price": 1.49, "location": "Aisle 1"],
            ["id": "product:4", "type": "product", "barcode": "000000000004", "name": "Broccoli", "emoji": "🥦", "color": "green", "category": "Produce", "price": 1.69, "location": "Aisle 1"],
            ["id": "product:5", "type": "product", "barcode": "000000000005", "name": "Cucumber", "emoji": "🥒", "color": "green", "category": "Produce", "price": 0.99, "location": "Aisle 1"],
            ["id": "product:6", "type": "product", "barcode": "000000000006", "name": "Salad", "emoji": "🥗", "color": "green", "category": "Produce", "price": 2.99, "location": "Aisle 1"],
            ["id": "product:7", "type": "product", "barcode": "000000000007", "name": "Corn", "emoji": "🌽", "color": "yellow", "category": "Produce", "price": 0.50, "location": "Aisle 1"],
            ["id": "product:8", "type": "product", "barcode": "000000000008", "name": "Potato", "emoji": "🥔", "color": "brown", "category": "Produce", "price": 0.99, "location": "Aisle 1"],
            ["id": "product:9", "type": "product", "barcode": "000000000009", "name": "Garlic", "emoji": "🧄", "color": "brown", "category": "Produce", "price": 0.50, "location": "Aisle 1"],
            ["id": "product:10", "type": "product", "barcode": "000000000010", "name": "Onion", "emoji": "🧅", "color": "brown", "category": "Produce", "price": 0.79, "location": "Aisle 1"],
            ["id": "product:11", "type": "product", "barcode": "000000000011", "name": "Tomato", "emoji": "🍅", "color": "red", "category": "Produce", "price": 1.29, "location": "Aisle 1"],
            ["id": "product:12", "type": "product", "barcode": "000000000012", "name": "Bell Pepper", "emoji": "🫑", "color": "green", "category": "Produce", "price": 0.99, "location": "Aisle 1"],
            // Fruit
            ["id": "product:13", "type": "product", "barcode": "000000000013", "name": "Cherries", "emoji": "🍒", "color": "red", "category": "Produce", "price": 3.99, "location": "Aisle 2"],
            ["id": "product:14", "type": "product", "barcode": "000000000014", "name": "Strawberry", "emoji": "🍓", "color": "red", "category": "Produce", "price": 2.99, "location": "Aisle 2"],
            ["id": "product:15", "type": "product", "barcode": "000000000015", "name": "Grapes", "emoji": "🍇", "color": "purple", "category": "Produce", "price": 2.49, "location": "Aisle 2"],
            ["id": "product:16", "type": "product", "barcode": "000000000016", "name": "Red Apple", "emoji": "🍎", "color": "red", "category": "Produce", "price": 1.99, "location": "Aisle 2"],
            ["id": "product:17", "type": "product", "barcode": "000000000017", "name": "Watermelon", "emoji": "🍉", "color": ["red", "green"], "category": "Produce", "price": 4.99, "location": "Aisle 2"],
            ["id": "product:18", "type": "product", "barcode": "000000000018", "name": "Tangerine", "emoji": "🍊", "color": "orange", "category": "Produce", "price": 2.49, "location": "Aisle 2"],
            ["id": "product:19", "type": "product", "barcode": "000000000019", "name": "Lemon", "emoji": "🍋", "color": "yellow", "category": "Produce", "price": 0.99, "location": "Aisle 2"],
            ["id": "product:20", "type": "product", "barcode": "000000000020", "name": "Pineapple", "emoji": "🍍", "color": "yellow", "category": "Produce", "price": 2.99, "location": "Aisle 2"],
            ["id": "product:21", "type": "product", "barcode": "000000000021", "name": "Banana", "emoji": "🍌", "color": "yellow", "category": "Produce", "price": 0.49, "location": "Aisle 2"],
            ["id": "product:22", "type": "product", "barcode": "000000000022", "name": "Avocado", "emoji": "🥑", "color": ["green", "yellow"], "category": "Produce", "price": 1.49, "location": "Aisle 2"],
            ["id": "product:23", "type": "product", "barcode": "000000000023", "name": "Green Apple", "emoji": "🍏", "color": "green", "category": "Produce", "price": 1.99, "location": "Aisle 2"],
            ["id": "product:24", "type": "product", "barcode": "000000000024", "name": "Melon", "emoji": "🍈", "color": ["green", "yellow"], "category": "Produce", "price": 3.49, "location": "Aisle 2"],
            ["id": "product:25", "type": "product", "barcode": "000000000025", "name": "Pear", "emoji": "🍐", "color": "green", "category": "Produce", "price": 1.49, "location": "Aisle 2"],
            ["id": "product:26", "type": "product", "barcode": "000000000026", "name": "Kiwi", "emoji": "🥝", "color": "green", "category": "Produce", "price": 1.99, "location": "Aisle 2"],
            ["id": "product:27", "type": "product", "barcode": "000000000027", "name": "Mango", "emoji": "🥭", "color": ["red", "yellow", "green"], "category": "Produce", "price": 1.99, "location": "Aisle 2"],
            ["id": "product:28", "type": "product", "barcode": "000000000028", "name": "Coconut", "emoji": "🥥", "color": ["brown", "white"], "category": "Produce", "price": 2.49, "location": "Aisle 2"],
            ["id": "product:29", "type": "product", "barcode": "000000000029", "name": "Blueberries", "emoji": "🫐", "color": "blue", "category": "Produce", "price": 3.99, "location": "Aisle 2"],
            ["id": "product:30", "type": "product", "barcode": "000000000030", "name": "Ginger Root", "emoji": "🫚", "color": "brown", "category": "Produce", "price": 0.89, "location": "Aisle 2"],
            // Bakery
            ["id": "product:31", "type": "product", "barcode": "000000000031", "name": "Cake", "emoji": "🍰", "color": ["yellow", "white"], "category": "Bakery", "price": 5.99, "location": "Aisle 3"],
            ["id": "product:32", "type": "product", "barcode": "000000000032", "name": "Cookie", "emoji": "🍪", "color": "brown", "category": "Bakery", "price": 2.99, "location": "Aisle 3"],
            ["id": "product:33", "type": "product", "barcode": "000000000033", "name": "Doughnut", "emoji": "🍩", "color": "brown", "category": "Bakery", "price": 1.99, "location": "Aisle 3"],
            ["id": "product:34", "type": "product", "barcode": "000000000034", "name": "Cupcake", "emoji": "🧁", "color": ["yellow", "white"], "category": "Bakery", "price": 2.99, "location": "Aisle 3"],
            ["id": "product:35", "type": "product", "barcode": "000000000035", "name": "Bagel", "emoji": "🥯", "color": "brown", "category": "Bakery", "price": 1.49, "location": "Aisle 3"],
            ["id": "product:36", "type": "product", "barcode": "000000000036", "name": "Bread", "emoji": "🍞", "color": "brown", "category": "Bakery", "price": 2.99, "location": "Aisle 3"],
            ["id": "product:37", "type": "product", "barcode": "000000000037", "name": "Baguette", "emoji": "🥖", "color": "brown", "category": "Bakery", "price": 2.49, "location": "Aisle 3"],
            ["id": "product:38", "type": "product", "barcode": "000000000038", "name": "Pretzel", "emoji": "🥨", "color": "brown", "category": "Bakery", "price": 1.99, "location": "Aisle 3"],
            ["id": "product:39", "type": "product", "barcode": "000000000039", "name": "Croissant", "emoji": "🥐", "color": "brown", "category": "Bakery", "price": 1.89, "location": "Aisle 3"],
            // Dairy
            ["id": "product:40", "type": "product", "barcode": "000000000040", "name": "Cheese", "emoji": "🧀", "color": "yellow", "category": "Dairy", "price": 3.99, "location": "Aisle 4"],
            ["id": "product:41", "type": "product", "barcode": "000000000041", "name": "Butter", "emoji": "🧈", "color": "yellow", "category": "Dairy", "price": 2.99, "location": "Aisle 4"],
            ["id": "product:42", "type": "product", "barcode": "000000000042", "name": "Ice Cream", "emoji": "🍨", "color": ["white", "brown"], "category": "Dairy", "price": 4.99, "location": "Aisle 4"],
            // Home
            ["id": "product:43", "type": "product", "barcode": "000000000043", "name": "Bolt", "emoji": "🔩", "color": "silver", "category": "Home", "price": 0.50, "location": "Aisle 5"],
            ["id": "product:44", "type": "product", "barcode": "000000000044", "name": "Hammer", "emoji": "🔨", "color": "black", "category": "Home", "price": 15.99, "location": "Aisle 5"],
            ["id": "product:45", "type": "product", "barcode": "000000000045", "name": "Wrench", "emoji": "🔧", "color": "silver", "category": "Home", "price": 14.99, "location": "Aisle 5"],
            // Office
            ["id": "product:46", "type": "product", "barcode": "000000000046", "name": "Scissors", "emoji": "✂️", "color": "red", "category": "Office", "price": 12.99, "location": "Aisle 6"],
            ["id": "product:47", "type": "product", "barcode": "000000000047", "name": "Paper Clip", "emoji": "📎", "color": "silver", "category": "Office", "price": 2.99, "location": "Aisle 6"],
            ["id": "product:48", "type": "product", "barcode": "000000000048", "name": "Push Pin", "emoji": "📌", "color": "red", "category": "Office", "price": 3.49, "location": "Aisle 6"]
        ]

        
        // Write data to database.
        for (_, var productData) in productsData.enumerated() {
            // Create a document
            let id = productData.removeValue(forKey: "id") as? String
            let document = MutableDocument(id: id, data: productData)
            
            // If the data has an emoji string, convert it to an image and add it to the document.
            var image: UIImage? = nil
            if let emoji = document["emoji"].string {
                image = self.image(from: emoji)
                if let pngData = image?.pngData() {
                    document["image"].blob = Blob(contentType: "image/png", data: pngData)
                }
            }
            try! collection.save(document: document)
            
            // If the data document has an image, generate an embedding and update the document.
            if let image = image {
                DispatchQueue.global().async(qos: .userInitiated) {
                    if let embedding = AI.shared.embedding(for: image, attention: .none) {
                        document["embedding"].array = MutableArrayObject(data: embedding)
                        try! collection.save(document: document)
                    }
                }
            }
        }
    }
    
    private func image(from string: String) -> UIImage {
        let nsString = string as NSString
        let font = UIFont.systemFont(ofSize: 160)
        let stringAttributes = [NSAttributedString.Key.font: font]
        let textSize = nsString.size(withAttributes: stringAttributes)
        let squareSize = max(textSize.width, textSize.height)

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: squareSize, height: squareSize))
        let image = renderer.image { context in
            let rect = CGRect(x: (squareSize - textSize.width) / 2, y: (squareSize - textSize.height) / 2, width: textSize.width, height: textSize.height)
            nsString.draw(in: rect, withAttributes: stringAttributes)
        }

        return image
    }
    
    // MARK: - Testing
    
    private func test() {
        // Full text search
        print("Full text search: \(search(string: "Green"))")
        print()
        
        // Vector search
        if let embedding = AI.shared.embedding(for: image(from: "🫑")) {
            print("Full text search: \(self.search(vector: embedding))")
            print()
        }
        
        // Add to cart and cart total
        print("Cart total before adding product: \(cartTotal)")
        addToCart(product: Product(name: "Broccoli", price: 1.69, location: "Aisle 1", image: image(from: "🥦")))
        print("Cart total after adding product: \(cartTotal)")
        print()
        
        // Clear cart
        clearCart()
        print("Cart total after clearing cart: \(cartTotal)")
    }
}
