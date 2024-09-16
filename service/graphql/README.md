# GraphQL Integration

Access our intelligence services using GraphQL for real-time insights and data processing. The GraphQL endpoint is `/graphql`.

[See All Intelligence Services](../README.md)

## Service Setup

To set up the service:

1. **Install Golang:** Ensure Golang is installed
2. **Set Environment Variables:** 
   - Set `OPENAI_API_KEY` in your environment
   - Optionally, set `PORT` (default is 8080)
   - You can define these variables directly in your environment or use an `intelligence.env` file in the root directory of your project like the following:
     ```
     OPENAI_API_KEY=your_openai_api_key
     PORT=8080
     ```
3. **Start the Service:** Run `main.go`

### Example CURL Call

Here is an example of how to make a CURL call directly to the intelligence service:

```sh
curl -X POST "http://localhost:8080/graphql" \
     -H "Content-Type: application/json" \
     -d '{"query": "query { sentiment(text: \"I am happy\") }"}'
```

## Schema

```graphql
schema {
  query: Query
}

type Query {
  sentiment(text: String!): String!
  classification(text: String, files: [InputBlob!], labels: [String!]!): String!
  extraction(text: String, files: [InputBlob!], labels: [String!]!): JSON!
  correctedGrammar(text: String!): String!
  generatedText(prompt: String!, files: [InputBlob!], maxWords: Int): String!
  generatedImage(prompt: String!, size: String, quality: String, style: String): Blob!
  masked(text: String!, labels: [String!]!): String!
  similarity(text1: String!, text2: String!): Float!
  summary(text: String!, maxWords: Int!): String!
  translation(text: String!, toLanguage: String!): String!
  embeddings(texts: [String!]!): [[Float!]!]!
  moderation(text: String!): ModerationResponse!
}

type Blob {
  contentType: String!
  base64: String!
}

type InputBlob {
  contentType: String!
  base64: String!
}

type ModerationResponse {
  flagged: Boolean!
  categories: ModerationCategories!
  categoryScores: ModerationCategoryScores!
}

type ModerationCategories {
  sexual: Boolean!
  hate: Boolean!
  harassment: Boolean!
  selfHarm: Boolean!
  sexualMinors: Boolean!
  hateThreatening: Boolean!
  violenceGraphic: Boolean!
  selfHarmIntent: Boolean!
  selfHarmInstructions: Boolean!
  harassmentThreatening: Boolean!
  violence: Boolean!
}

type ModerationCategoryScores {
  sexual: Float!
  hate: Float!
  harassment: Float!
  selfHarm: Float!
  sexualMinors: Float!
  hateThreatening: Float!
  violenceGraphic: Float!
  selfHarmIntent: Float!
  selfHarmInstructions: Float!
  harassmentThreatening: Float!
  violence: Float!
}

scalar JSON
```

## Query Examples

Here are example GraphQL queries for the intelligence services:

### Sentiment Analysis

```graphql
query {
  sentiment(text: "I am happy")
}
```

```json
{
  "data": {
    "sentiment": "positive"
  }
}
```

### Classification

```graphql
query {
  classification(text: "My password is leaked.", labels: ["urgent", "not urgent"])
}
```

```json
{
  "data": {
    "classification": "urgent"
  }
}
```

### Extraction

```graphql
query {
  extraction(text: "John Doe lives in New York and works for Acme Corp.", labels: ["person", "location", "organization"])
}
```

```json
{
  "data": {
    "extraction": {
      "person": "John Doe",
      "location": "New York",
      "organization": "Acme Corp."
    }
  }
}
```

### Image Generation

```graphql
query {
  generatedImage(prompt: "A beautiful beach in a photorealistic style", size: "1024x1024")
}
```

```json
{
  "data": {
    "generatedImage": {
      "contentType": "image/png",
      "base64": "iVBORw0KGgoAAAANSU..."
    }
  }
}
```
