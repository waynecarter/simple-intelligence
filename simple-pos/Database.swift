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
    
    private let products: [Product] = [
        Product(name: "Bell Pepper", price: "$2.00", location: "Isle 5", image: image(from: "🫑")),
        Product(name: "Broccoli", price: "$1.50", location: "Isle 2", image: image(from: "🥦")),
        Product(name: "Lettuce", price: "$1.00", location: "Isle 4", image: image(from: "🥬")),
        Product(name: "Cucumber", price: "$1.20", location: "Isle 3", image: image(from: "🥒")),
        Product(name: "Green Apple", price: "$2.50", location: "Isle 6", image: image(from: "🍏")),
        Product(name: "Avocado", price: "$2.80", location: "Isle 1", image: image(from: "🥑"))
    ]
    
    struct Product {
        let name: String
        let price: String
        let location: String
        let image: UIImage
    }
    
    private init() {
        database = try! CouchbaseLiteSwift.Database(name: "pos")
        collection = try! database.defaultCollection()
        
        // If the database is empty, initialize it w/ the demo data.
        if collection.count == 0  {
            // TODO: Populate the database with the demo data.
        }
    }
    
    func search(using string: String) -> [Product] {
        // TODO: Search database.
        return [ products[1], products[2], products[3] ]
    }
    
    func search(using vector: [NSNumber]) -> [Product] {
        // TODO: Search database.
        return [ products[0] ]
    }
    
    func addToCart(product: Product) {
        // TODO: Add product to the items in the cart doc.
        print("\(product.name) added to cart")
    }
    
    var cartTotal: String {
        // TODO: Get from database.
        return "$3.50"
    }
    
    func deleteCart() {
        // TODO: Delete the cart doc from the database.
        print("Cart deleted")
    }
    
    private static func image(from string: String) -> UIImage {
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
}
