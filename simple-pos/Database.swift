//
//  Database.swift
//  simple-pos
//
//  Created by Wayne Carter on 5/18/24.
//

import UIKit
import CouchbaseLiteSwift

class Database {
    static let shared = Database()
    
    private let database: CouchbaseLiteSwift.Database
    private let collection: CouchbaseLiteSwift.Collection
    
    struct Product {
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
    }
    
    private init() {
        database = try! CouchbaseLiteSwift.Database(name: "pos")
        collection = try! database.defaultCollection()
        
        // If the database is empty, initialize it with the demo data.
        if collection.count == 0  {
            loadDemoData(in: collection)
        }
        
        // Initialize the full-text search index on the "name" and "color" fields.
        let ftsIndex = FullTextIndexConfiguration(["name"])
        try! collection.createIndex(withName: "NameFullTextIndex", config: ftsIndex)
        
        // Initialize the vector index on the "embedding" field for image search.
        var vectorIndex = VectorIndexConfiguration(expression: "embedding", dimensions: 768, centroids: 2)
        vectorIndex.metric = .cosine
        try! collection.createIndex(withName: "ImageVectorIndex", config: vectorIndex)
    }
    
    // MARK: - Search
    
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
                AND MATCH(NameFullTextIndex, $search)
            ORDER BY RANK(NameFullTextIndex)
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
    
    func search(vector: [NSNumber]) -> [Product] {
        // SQL
        let sql = """
            SELECT name, price, location, image, VECTOR_DISTANCE(ImageVectorIndex) AS distance
            FROM _
            WHERE type = "product"
                AND VECTOR_MATCH(ImageVectorIndex, $embedding, 10)
                AND VECTOR_DISTANCE(ImageVectorIndex) < 0.35
            ORDER BY VECTOR_DISTANCE(ImageVectorIndex)
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
            print("Database.searchVector: \(error.localizedDescription)")
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
    
    // MARK: - Util
    
    private func loadDemoData(in collection: CouchbaseLiteSwift.Collection) {
        let productsData: [[String : Any]] = [
            // Vegetables
            ["type":"product", "name":"Hot Pepper", "emoji":"🌶️", "color":"red", "category":"Produce", "price":0.99, "location":"Isle 2"],
            ["type":"product", "name":"Carrot", "emoji":"🥕", "color":"orange", "category":"Produce", "price":0.79, "location":"Isle 2"],
            ["type":"product", "name":"Lettuce", "emoji":"🥬", "color":"green", "category":"Produce", "price":1.49, "location":"Isle 2"],
            ["type":"product", "name":"Broccoli", "emoji":"🥦", "color":"green", "category":"Produce", "price":1.69, "location":"Isle 2"],
            ["type":"product", "name":"Cucumber", "emoji":"🥒", "color":"green", "category":"Produce", "price":0.99, "location":"Isle 2"],
            ["type":"product", "name":"Salad", "emoji":"🥗", "color":"green", "category":"Produce", "price":2.99, "location":"Isle 2"],
            ["type":"product", "name":"Corn", "emoji":"🌽", "color":"yellow", "category":"Produce", "price":0.50, "location":"Isle 2"],
            ["type":"product", "name":"Potato", "emoji":"🥔", "color":"brown", "category":"Produce", "price":0.99, "location":"Isle 2"],
            ["type":"product", "name":"Garlic", "emoji":"🧄", "color":"brown", "category":"Produce", "price":0.50, "location":"Isle 2"],
            ["type":"product", "name":"Onion", "emoji":"🧅", "color":"brown", "category":"Produce", "price":0.79, "location":"Isle 2"],
            ["type":"product", "name":"Tomato", "emoji":"🍅", "color":"red", "category":"Produce", "price":1.29, "location":"Isle 2"],
            ["type":"product", "name":"Bell Pepper", "emoji":"🫑", "color":"green", "category":"Produce", "price":0.99, "location":"Isle 2"],
            // Fruit
            ["type":"product", "name":"Cherries", "emoji":"🍒", "color":"red", "category":"Produce", "price":3.99, "location":"Isle 3"],
            ["type":"product", "name":"Strawberry", "emoji":"🍓", "color":"red", "category":"Produce", "price":2.99, "location":"Isle 3"],
            ["type":"product", "name":"Grapes", "emoji":"🍇", "color":"purple", "category":"Produce", "price":2.49, "location":"Isle 3"],
            ["type":"product", "name":"Red Apple", "emoji":"🍎", "color":"red", "category":"Produce", "price":1.99, "location":"Isle 3"],
            ["type":"product", "name":"Watermelon", "emoji":"🍉", "color":["red", "green"], "category":"Produce", "price":4.99, "location":"Isle 3"],
            ["type":"product", "name":"Tangerine", "emoji":"🍊", "color":"orange", "category":"Produce", "price":2.49, "location":"Isle 3"],
            ["type":"product", "name":"Lemon", "emoji":"🍋", "color":"yellow", "category":"Produce", "price":0.99, "location":"Isle 3"],
            ["type":"product", "name":"Pineapple", "emoji":"🍍", "color":"yellow", "category":"Produce", "price":2.99, "location":"Isle 3"],
            ["type":"product", "name":"Banana", "emoji":"🍌", "color":"yellow", "category":"Produce", "price":0.49, "location":"Isle 3"],
            ["type":"product", "name":"Avocado", "emoji":"🥑", "color":["green", "yellow"], "category":"Produce", "price":1.49, "location":"Isle 3"],
            ["type":"product", "name":"Green Apple", "emoji":"🍏", "color":"green", "category":"Produce", "price":1.99, "location":"Isle 3"],
            ["type":"product", "name":"Melon", "emoji":"🍈", "color":["green", "yellow"], "category":"Produce", "price":3.49, "location":"Isle 3"],
            ["type":"product", "name":"Pear", "emoji":"🍐", "color":"green", "category":"Produce", "price":1.49, "location":"Isle 3"],
            ["type":"product", "name":"Kiwi", "emoji":"🥝", "color":"green", "category":"Produce", "price":1.99, "location":"Isle 3"],
            ["type":"product", "name":"Mango", "emoji":"🥭", "color":["red", "yellow", "green"], "category":"Produce", "price":1.99, "location":"Isle 3"],
            ["type":"product", "name":"Coconut", "emoji":"🥥", "color":["brown", "white"], "category":"Produce", "price":2.49, "location":"Isle 3"],
            ["type":"product", "name":"Blueberries", "emoji":"🫐", "color":"blue", "category":"Produce", "price":3.99, "location":"Isle 3"],
            ["type":"product", "name":"Ginger Root", "emoji":"🫚", "color":"brown", "category":"Produce", "price":0.89, "location":"Isle 3"],
            // Bakery
            ["type":"product", "name":"Cake", "emoji":"🍰", "color":["yellow", "white"], "category":"Bakery", "price":5.99, "location":"Isle 7"],
            ["type":"product", "name":"Cookie", "emoji":"🍪", "color":"brown", "category":"Bakery", "price":2.99, "location":"Isle 7"],
            ["type":"product", "name":"Doughnut", "emoji":"🍩", "color":"brown", "category":"Bakery", "price":1.99, "location":"Isle 7"],
            ["type":"product", "name":"Cupcake", "emoji":"🧁", "color":["yellow", "white"], "category":"Bakery", "price":2.99, "location":"Isle 7"],
            ["type":"product", "name":"Bagel", "emoji":"🥯", "color":"brown", "category":"Bakery", "price":1.49, "location":"Isle 7"],
            ["type":"product", "name":"Bread", "emoji":"🍞", "color":"brown", "category":"Bakery", "price":2.99, "location":"Isle 7"],
            ["type":"product", "name":"Baguette", "emoji":"🥖", "color":"brown", "category":"Bakery", "price":2.49, "location":"Isle 7"],
            ["type":"product", "name":"Pretzel", "emoji":"🥨", "color":"brown", "category":"Bakery", "price":1.99, "location":"Isle 7"],
            ["type":"product", "name":"Croissant", "emoji":"🥐", "color":"brown", "category":"Bakery", "price":1.89, "location":"Isle 7"],
            // Dairy
            ["type":"product", "name":"Cheese", "emoji":"🧀", "color":"yellow", "category":"Dairy", "price":3.99, "location":"Isle 8"],
            ["type":"product", "name":"Butter", "emoji":"🧈", "color":"yellow", "category":"Dairy", "price":2.99, "location":"Isle 8"],
            ["type":"product", "name":"Ice Cream", "emoji":"🍨", "color":["white", "brown"], "category":"Dairy", "price":4.99, "location":"Isle 8"]
        ]
        
        // Write data to database.
        for (_, productData) in productsData.enumerated() {
            // Create a document
            let document = MutableDocument(data: productData)
            
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
                AI.shared.foregroundFeatureEmbedding(for: image, fitTo: CGSize(width: 100, height: 100)) { embedding in
                    if let embedding = embedding {
                        document["embedding"].array = MutableArrayObject(data: embedding)
                        try! collection.save(document: document)
                    }
                }
            }
        }
    }
    
    func image(from string: String) -> UIImage {
        let nsString = string as NSString
        let font = UIFont.systemFont(ofSize: 160)
        let stringAttributes = [NSAttributedString.Key.font: font]
        let imageSize = nsString.size(withAttributes: stringAttributes)

        let renderer = UIGraphicsImageRenderer(size: imageSize)
        let image = renderer.image { _ in
            nsString.draw( at: CGPoint.zero, withAttributes: stringAttributes)
        }

        return image
    }
    
    // MARK: - Testing
    
    private func test() {
        // Full text search
        print("Full text search: \(search(string: "Green"))")
        print()
        
        // Vector search
        AI.shared.foregroundFeatureEmbedding(for: image(from: "🫑")) { embedding in
            if let embedding {
                print("Full text search: \(self.search(vector: embedding))")
                print()
            }
        }
        
        // Add to cart and cart total
        print("Cart total before adding product: \(cartTotal)")
        addToCart(product: Product(name: "Broccoli", price: 1.69, location: "Isle 2", image: image(from: "🥦")))
        print("Cart total after adding product: \(cartTotal)")
        print()
        
        // Clear cart
        clearCart()
        print("Cart total after clearing cart: \(cartTotal)")
    }
}
