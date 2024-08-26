# Intelligence Services

## Overview

This provides an overview of the intelligence services that have been implemented and how to use them. Each service is designed to process text data in different ways, returning structured results that can be used for further analysis, decision making, or enrichment.

### Services
* **Sentiment Analysis:** Analyzes the sentiment of a given text and returns whether the sentiment is positive, negative, neutral, or mixed.
* **Classification:** Classifies text into predefined categories.
* **Entity Extraction:** Extracts entities such as persons, locations, or organizations from text.
* **Grammar Correction:** Corrects grammatical errors in a given text.
* **Text Generation:** Generates text based on a given prompt.
* **Masking:** Masks specified entities (e.g., names, emails) in the text.
* **Similarity Analysis:** Compares two texts and returns a similarity score.
* **Summarization:** Summarizes a longer piece of text into a shorter form.
* **Translation:** Translates text from one language to another.
* **Text Embedding:** Converts text into a numerical vector for machine learning models.

## Service Setup

### Start
To start the intelligence service, follow these steps:

1. **Ensure all dependencies are installed:** Make sure you have Python installed and the required packages.
2. **Load environment variables:** Ensure that the `OPENAI_API_KEY` is set in the environment variables. The service uses port 8080 by default and this can be overridded using the `PORT` environment variable. The variables can be set directly in your environment or you can create a `intelligence.env` file in the project directory with the variables defined as follows:
   ```text
   OPENAI_API_KEY=your_openai_api_key
   PORT=8080
   ```
3. **Start the service:** Run `intelligence.go`

#### Example cURL Call
Here is an example of how to make a cURL call directly to the intelligence service:

```sh
curl -X POST "http://localhost:8080/intelligence?model=sentiment" \
     -H "Content-Type: application/json" \
     -d '{"text": "I am happy"}'
```

## Query Setup

### Enable CURL
To use CURL in your SQL++ queries with Couchbase Server, you'll need to configure the allowed URLs in the server settings. Here's how to do it:

1. Open your web browser and go to the Couchbase Server dashboard.
2. Navigate to **Settings > Query Settings > Advanced Query Settings**
3. Set **CURL() Function Access** to `Restricted`
4. Add an **Allowed CURL URL** with the value `http://localhost:8080/intelligence`
5. Save the changes

### Create UDF
To integrate these services with Couchbase Server, you can create a User-Defined Function (UDF) that makes a cURL call to the intelligence service. Create the UDF in Couchbase Server using the following query:

```sql
CREATE FUNCTION intelligence(model, params) {
    CURL("http://localhost:8080/intelligence?model=" || model, {
        "request": "POST",
        "header": ["Content-Type: application/json"],
        "connect-timeout": 5000,
        "data": ENCODE_JSON(params)
    })
};
```

## Query Examples
You can use the intelligence UDF in your SQL++ queries within Couchbase to perform various types of analyses. Here are examples of queries and results:

### Sentiment Analysis

```sql
SELECT intelligence("sentiment", { "text": "I am happy" }).sentiment;
```

```javascript
{
  "sentiment": "positive"
}
```

### Text Classification

```sql
SELECT intelligence("classification", { "text": "My password is leaked.", "labels": ["urgent", "not urgent"] }).classification;
```

```javascript
{
  "classification": "urgent"
}
```

### Entity Extraction

```sql
SELECT intelligence("extraction", { "text": "John Doe lives in New York and works for Acme Corp.", "labels": ["person", "location", "organization"] }).extraction;
```

```javascript
{
  "extraction": {
    "location": "New York",
    "organization": "Acme Corp.",
    "person": "John Doe"
  }
}
```

### Grammar Correction

```sql
SELECT intelligence("corrected_grammar", { "text": "This sentence have some mistake" }).corrected_grammar;
```

```javascript
{
  "corrected_grammar": "This sentence has some mistakes."
}
```

### Text Generation

```sql
SELECT intelligence("generated_text", { "prompt": "Generate a concise, cheerful email title for a summer bike sale with 20% discount." }).generated_text;
```

```javascript
{
  "generated_text": "Pedal into Summer: Enjoy 20% Off Our Bike Sale!"
}
```

### Masking

```sql
SELECT intelligence("masked", { "text": "John Doe lives in New York. His email is john.doe@example.com.", "labels": ["person", "email"] }).masked;
```

```javascript
{
  "masked": "[MASKED] lives in New York. His email is [MASKED]."
}
```

### Similarity Analysis

```sql
SELECT intelligence("similarity", { "text1": "text1": "JavaScript", "text2": "JS" }).similarity;
```

```javascript
{
  "similarity": 0.9
}
```

### Summarization

```sql
SELECT intelligence("summary", { "text": "Apache Spark is a unified analytics engine for large-scale data processing. It provides high-level APIs in Java, Scala, Python, and R, and an optimized engine that supports general execution graphs. It also supports a rich set of higher-level tools including Spark SQL for SQL and structured data processing, pandas API on Spark for pandas workloads, MLlib for machine learning, GraphX for graph processing, and Structured Streaming for incremental computation and stream processing.", "max_words": 50 }).summary;
```

```javascript
{
  "summary": "Apache Spark is a unified analytics engine for large-scale data processing, offering high-level APIs in multiple languages and tools like Spark SQL, MLlib, GraphX, and Structured Streaming for various data processing tasks, including SQL, machine learning, and stream processing."
}
```

### Translation

```sql
SELECT intelligence("translation", { "text": "Hello, how are you?", "to_language": "es" }).translation;
```

```javascript
{
  "translation": "Hola, ¿cómo estás?"
}
```

### Text Embedding

```sql
SELECT intelligence("embeddings", { "text": "The quick brown fox jumps over the lazy dog" }).embeddings;
```

```javascript
{
  "embeddings": [
    [ -0.020832369104027748, -0.016892163082957268, ..., 0.024707552045583725 ]
  ]
}
```

## Eventing Setup
To set up an eventing function in Couchbase Server that enriches documents with intelligence, follow these steps:

### Create Function
1. Log in to the Couchbase Server UI and go to **Eventing**
2. Add a new function and name it something like `EnrichSentiment`

### Create Aliases
3. In the function setting:
   1. Create a **URL Alias** with the following details:
      - **Name:** `intelligenceService`
      - **URL:** `http://localhost:8080/intelligence`
   1. Create a **Bucket Alias** with the following details:
      - **Name:** `targetBucket`
      - **Bucket:** Select the appropriate bucket where the enriched documents should be saved.

### Code
Use the following JavaScript for the function's code that enriches documents with a `message` field with the message's `sentiment`.:

```javascript
function OnUpdate(doc, meta) {
    if (!doc.message) { return; }

    let response = curl('POST', intelligenceService, {
        params: {
            'model': 'sentiment'
        },
        body: {
            'text': doc.message
        }
    });
    
    if (response.status === 200) {
        let intelligence = response.body;
        let sentiment = intelligence.sentiment;

        if (sentiment) {
            doc.sentiment = sentiment;
            targetBucket[meta.id] = doc;
        }
    }
}
```