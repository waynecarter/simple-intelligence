# Classification: Automatically Categorizing Text and Images

Classification is a core AI service that helps businesses efficiently categorize and organize large amounts of unstructured data. Whether it’s classifying product reviews, support tickets, or identifying objects in images, automated classification accelerates workflows and optimizes resource allocation.

By using classification, companies can quickly sift through text or image data and assign predefined categories, enabling faster decision-making and improving accuracy across various business operations.

## Table of Contents
- [Solution](#solution)
- [Real-Time Query](#real-time-query)
- [Data Enrichment](#data-enrichment)
- [Real-World Application](#real-world-application)
- [Classification with GraphQL and Node.js](#classification-with-graphql-and-nodejs)

## Solution

The Intelligence Service offers two approaches for classification: **real-time querying** for on-demand results and **data enrichment** for faster, recurring queries.

- **Real-time Query**: Use direct queries to instantly classify text or images into predefined categories, allowing your team to act quickly.
- **Data Enrichment**: Set up automatic classification that processes incoming data and stores the results for faster future queries. This reduces the need for real-time processing each time you access the data, improving scalability.

## Real-Time Query

You can query the Intelligence Service for real-time classification of text or images.

- **SQL**
  ```sql
  SELECT intelligence("classification", { "text": "This is an urgent issue.", "labels": ["urgent", "not urgent"] }).classification;
  ```

- **REST**
  ```bash
  curl -X POST "http://localhost:8080/intelligence" \
     -H "Content-Type: application/json" \
     -d '{"model": "classification", "text": "This is an urgent issue.", "labels": ["urgent", "not urgent"]}'
  ```

- **GraphQL**
  ```graphql
  query {
    classification(text: "This is an urgent issue.", labels: ["urgent", "not urgent"])
  }
  ```
  
### Output Examples

- **SQL and REST**
  ```json
  {
    "classification": "urgent"
  }
  ```

- **GraphQL**
  ```json
  {
    "data": {
      "classification": "urgent"
    }
  }
  ```

## Data Enrichment

In addition to real-time queries, you can use enrichment to process incoming data and store intelligence for faster future queries. This approach is useful when feedback is processed in bulk or repeatedly queried, as the enriched data can be quickly accessed without needing real-time processing for each request. This helps improve performance and scalability, especially in high-volume environments.

Here’s an example of how you can set up a data update trigger to enrich incoming feedback with classification information:

```javascript
function OnUpdate(doc, meta) {
    if (!doc.message) { return; }

    let response = curl('POST', intelligenceService, { body: {
        'model': 'classification',
        'text': doc.message,
        'labels': ['urgent', 'not urgent']
    }});
    
    if (response.status === 200) {
        let intelligence = response.body;
        let classification = intelligence.classification;

        if (classification) {
            doc.classification = classification;
            targetBucket[meta.id] = doc;
        }
    }
}
```

> **Performance Tip**: Use real-time queries when you need immediate, low-latency results, such as live customer feedback analysis. For scenarios where data is processed in bulk or queried repeatedly, enrichment allows for faster, pre-indexed data retrieval.
>
> You can also leverage the **Batch API** to retrieve multiple results in parallel. This enables faster bulk processing.

## Real-World Application

1. **Support Ticket Triage**: Classify support tickets as urgent or non-urgent to prioritize issues and improve response times.
2. **Product Feature Categorization**: Classify customer reviews based on the features or aspects they discuss, such as usability, performance, design, or customer service.
3. **Medical Diagnosis**: Automatically classify medical images or records based on disease categories, improving diagnostic speed and accuracy.
4. **Email Filtering**: Classify emails into predefined categories like spam, promotions, or important, enhancing email management and productivity.
5. **Image Recognition**: Use classification to identify objects in images, such as categorizing shapes or colors in product photos.
6. **Document Sorting**: Automatically organize documents by content type or importance for faster retrieval and better document management.
7. **News Article Categorization**: Classify news articles by topic, helping content platforms recommend relevant stories to users.

## Classification with GraphQL and Node.js

Here’s a full code example showing how to set up a Node.js app to query the classification service using the Apollo GraphQL client:

```js
const { ApolloClient, InMemoryCache, gql } = require('@apollo/client');
const fetch = require('node-fetch');

const client = new ApolloClient({
  uri: 'http://localhost:8080/graphql',
  cache: new InMemoryCache(),
  fetch
});

client.query({
  query: gql`
    query {
      classification(text: "This is an urgent issue.", labels: ["urgent", "not urgent"])
    }
  `
}).then(response => console.log(response.data.classification));
```

---

Stay tuned for updates—we’re continuously adding new features and content to the platform. Make sure to [watch this repository](https://github.com/waynecarter/simple-intelligence) to get notified about the latest.
