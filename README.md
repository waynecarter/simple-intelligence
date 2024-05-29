# simple-pos

## Image Search

The `Database.search(image: Image)` function demonstrates AI search and indexing capabilities. I utilizes SQL and Vector Search to find database results base on AI predictions.

```swift
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
```

## Vector Search

The `Database.search(vector: [Double])` function demonstrates the vector search and vector indexing capabilities.

### SQL

```sql
SELECT name, price, location, image
FROM products
WHERE VECTOR_MATCH(EmbeddingVectorIndex, $embedding, 10)
  AND VECTOR_DISTANCE(EmbeddingVectorIndex) < 0.25
ORDER BY VECTOR_DISTANCE(EmbeddingVectorIndex), name
```

### Query

```swift
// Create the query.
let query = try database.createQuery(sql)

// Set the query parameters.
query.parameters = Parameters()
    .setString(embedding, forName: "embedding")

// Execute the query.
let results = try query.execute()
```

### Indexing

```swift
// Initialize the vector index on the "embedding" field for image search.
var vectorIndex = VectorIndexConfiguration(expression: "embedding", dimensions: 768, centroids: 1000)
vectorIndex.metric = .cosine
try! collection.createIndex(withName: "EmbeddingVectorIndex", config: vectorIndex)
```

## Barcode Search

The `Database.search(barcode: String)` function demonstrates SQL query and indexing capabilities.

### SQL

```sql
SELECT name, price, location, image
FROM products
WHERE barcode = $barcode
LIMIT 1
```

### Query

```swift
// Create the query.
let query = try database.createQuery(sql)

// Set the query parameters.
query.parameters = Parameters()
    .setString(barcode, forName: "barcode")

// Execute the query.
let results = try query.execute()
```

### Indexing

```swift
// Initialize the value index on the "barcode" field for fast searching.
let barcodeIndex = ValueIndexConfiguration(["barcode"])
try! collection.createIndex(withName: "BarcodeIndex", config: barcodeIndex)
```

## Full-Text Search

The `Database.search(search: String)` function demonstrates full-text search and indexing capabilities.

### SQL

```sql
SELECT name, price, location, image
FROM products
WHERE MATCH(NameAndCategoryFullTextIndex, $search)
ORDER BY RANK(NameAndCategoryFullTextIndex), name
```

### Query

```swift
// Create the query.
let query = try database.createQuery(sql)

// Set the query parameters.
query.parameters = Parameters()
    .setString(search, forName: "search")

// Execute the query.
let results = try query.execute()
```

### Indexing

```swift
// Initialize the full-text search index on the "name" and "category" fields.
let ftsIndex = FullTextIndexConfiguration(["name", "category"])
try! collection.createIndex(withName: "NameAndCategoryFullTextIndex", config: ftsIndex)
```

## Sync

The `Database.startSync()` function demonstrates how to sync with a Couchbase Capella cloud endpoint.

```swift
// Set up the sync endpoint.
let target = URLEndpoint(url: endpoint.url)
var config = ReplicatorConfiguration(target: target)
config.addCollection(collection)
config.replicatorType = .pull
config.authenticator = BasicAuthenticator(username: endpoint.username, password: endpoint.password)

// Create and start the replicator.
let replicator = Replicator(config: config)
replicator.start()
```
