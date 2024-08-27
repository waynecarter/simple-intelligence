# Intelligence Service

## Overview

This document outlines the intelligence services implemented to process data. Each service is designed to deliver structured results for analysis, decision-making, and enrichment.

### Services

- **Sentiment Analysis:** Detects sentiment in text (positive, negative, neutral, or mixed)
- **Classification:** Categorizes text into predefined classes
- **Entity Extraction:** Identifies entities (e.g. persons, locations, organizations) within text
- **Grammar Correction:** Fixes grammatical errors
- **Text Generation:** Produces text from a prompt
- **Masking:** Hides specified entities (e.g. names, emails)
- **Similarity Analysis:** Compares texts and provides a similarity score
- **Summarization:** Condenses text into a shorter version
- **Translation:** Converts text between languages
- **Text Embedding:** Converts text into numerical vectors for machine learning
- **Moderation:** Identifies and flags inappropriate or harmful content in text

### Demo Videos

These demos showcase the intelligence services in action:

- [Query](https://github.com/waynecarter/simple-intelligence/raw/main/service/videos/intelligence-query.mov)
- [Enrichment](https://github.com/waynecarter/simple-intelligence/raw/main/service/videos/intelligence-query.mov)

## Service Setup

To set up the service:

1. **Install Golang:** Ensure Golang is installed
2. **Set Environment Variables:** 
   - Set `OPENAI_API_KEY` in your environment
   - Optionally, set `PORT` (default is 8080)
   - You can define these variables directly in your environment or use a `intelligence.env` file in the root directory of your project like the following:
     ```
     OPENAI_API_KEY=your_openai_api_key
     PORT=8080
     ```
3. **Start the Service:** Run `intelligence.go`

### Example cURL Call

Here is an example of how to make a cURL call directly to the intelligence service:

```sh
curl -X POST "http://localhost:8080/intelligence?model=sentiment" \
     -H "Content-Type: application/json" \
     -d '{"text": "I am happy"}'
```

## Query Setup

### Enable CURL

To use CURL in SQL++ queries with Couchbase Server:

1. Ensure [Couchbase Server](https://www.couchbase.com/downloads/?family=couchbase-server) is installed
2. Go to Couchbase Server dashboard
3. Navigate to **Settings > Query Settings > Advanced Query Settings**
4. Set **CURL() Function Access** to `Restricted`
5. Add an **Allowed CURL URL** with the value `http://localhost:8080/intelligence`
6. Save the changes

### Create UDF

Integrate the intelligence services with Couchbase Server using this User-Defined Function (UDF):

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

Here are SQL++ query examples using the intelligence UDF:

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
SELECT intelligence("generated_text", { "prompt": "Generate a concise, cheerful email title for a summer bike sale with 20% discount.", "max_words": 50 }).generated_text;
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
SELECT intelligence("similarity", { "text1": "JavaScript", "text2": "JS" }).similarity;
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

### Moderation

```sql
SELECT intelligence("moderation", { "text": "This is some harmful content." }).moderation;
```

```javascript
{
   "moderation": {
      "flagged": true,
      "categories": {
         "harassment": true,
         "harassment/threatening": true,
         "hate": false,
         "hate/threatening": false,
         "self-harm": false,
         "self-harm/instructions": false,
         "self-harm/intent": false,
         "sexual": false,
         "sexual/minors": false,
         "violence": true,
         "violence/graphic": false
      },
      "category_scores": {
         "harassment": 0.5665766596794128,
         "harassment/threatening": 0.503197431564331,
         "hate": 0.0006636827602051198,
         "hate/threatening": 0.00013561644300352782,
         "self-harm": 0.0000034303338907193393,
         "self-harm/instructions": 7.106075283758173e-9,
         "self-harm/intent": 2.732113273395953e-7,
         "sexual": 0.0003790947957895696,
         "sexual/minors": 0.000006095848675613524,
         "violence": 0.9586367011070251,
         "violence/graphic": 0.000556226703338325
      }
   }
}
```

## Eventing Setup

To set up an eventing function in Couchbase Server that enriches documents:

### Create Function
1. Log in to Couchbase Server UI and go to **Eventing**
2. Add a new function (e.g. EnrichSentiment)

### Create Aliases
In the function setting:
1. Create a **URL Alias**:
   * **Name:** `intelligenceService`
   * **URL:** `http://localhost:8080/intelligence`
2. Create a **Bucket Alias**:
   * **Name:** `targetBucket`
   * **Bucket:** Select the target bucket

### Code

Use the following JavaScript code in the function:

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
