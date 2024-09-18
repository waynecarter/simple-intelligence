# Sentiment Analysis: Understanding Customer Feedback

Businesses today receive massive amounts of feedback through social media, reviews, and support channels. Automating sentiment analysis helps teams respond faster, improve products, and boost customer satisfaction—without overwhelming resources.

By scaling sentiment analysis, companies can quickly prioritize issues, resolve customer pain points, and optimize resource allocation. Whether analyzing social channels or support tickets, real-time insights into customer sentiment drive product enhancements and foster lasting customer loyalty.

## Table of Contents
- [Solution](#solution)
- [Real-Time Query](#real-time-query)
- [Data Enrichment](#data-enrichment)
- [Real-World Application](#real-world-application)
- [Sentiment Analyzer with GraphQL and Node.js](#sentiment-analyzer-with-graphql-and-nodejs)

## Solution

The Intelligence Service offers two powerful approaches to handle sentiment analysis: **real-time querying** for immediate insights and **enrichment** for faster, recurring queries.

- **Real-time Query**: Use direct queries to the Intelligence Service to categorize feedback (positive, negative, neutral, or mixed) in real time, helping your team act quickly. 
- **Data Enrichment**: Use a data update trigger to automatically enrich feedback with sentiment data as it flows into your system. This allows you to index and query the enriched feedback faster, without needing real-time processing each time.

## Real-Time Query

The Intelligence Service offers real-time querying for immediate insights. You can directly query the service to categorize feedback in real time, helping your team respond quickly.

- **SQL**
  ```sql
  SELECT intelligence("sentiment", { "text": "I love the product but the shipping took too long!" }).sentiment;
  ```

- **REST**
  ```bash
  curl -X POST "http://localhost:8080/intelligence" \
       -H "Content-Type: application/json" \
       -d '{"model": "sentiment", "text": "I love the product but the shipping took too long!"}'
  ```

- **GraphQL**
  ```graphql
  query {
    sentiment(text: "I love the product but the shipping took too long!")
  }
  ```
  
### Output Examples

- **SQL and REST**
  ```json
  {
    "sentiment": "mixed"
  }
  ```

- **GraphQL**
  ```json
  {
    "data": {
      "sentiment": "mixed"
    }
  }
  ```

## Data Enrichment

In addition to real-time queries, you can use enrichment to process incoming data and store intelligence for faster future queries. This approach is useful when feedback is processed in bulk or repeatedly queried, as the enriched data can be quickly accessed without needing real-time processing for each request. This helps improve performance and scalability, especially in high-volume environments.

Here’s an example of how you can set up a data update trigger to enrich incoming feedback with sentiment information:

### Data Update Trigger

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

> **Performance Tip**: Use real-time queries when you need immediate, low-latency results, such as live customer feedback analysis. For scenarios where feedback is processed in bulk or queried repeatedly, enrichment allows for faster, pre-indexed data retrieval.
>
> You can also leverage the **Batch API** to retrieve multiple results in parallel, whether you're using real-time queries or enrichment. This enables faster bulk processing, especially in high-volume environments, and improves performance when handling simultaneous requests.

## Real-World Application

- **Social Media Feedback**: Track mentions of your brand across social platforms to quickly address concerns and improve engagement.
- **Customer Support Monitoring**: Analyze support tickets for sentiment to prioritize issues and improve satisfaction.
- **Product Reviews**: Scan reviews to identify strengths, weaknesses, and opportunities for product improvements.
- **Employee Feedback**: Analyze internal feedback to address concerns, improve culture, and boost retention.
- **Brand Health**: Monitor brand sentiment across digital channels to maintain a strong image and track campaign impact.
- **Crisis Management**: Track public sentiment during a PR crisis to adjust messaging in real time and mitigate damage.
- **Customer Surveys**: Analyze survey responses to spot trends and measure success.
- **Market Research**: Analyze competitor feedback to uncover opportunities and adjust your strategy.
- **Political Sentiment**: Track public opinion on candidates and issues to refine campaign messaging.

## Sentiment Analyzer with GraphQL and Node.js

Here’s a full code example showing how you can set up a Node.js app to query the sentiment analysis service using the Apollo GraphQL client:

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
      sentiment(text: "I love the product but the shipping took too long!")
    }
  `
}).then(response => console.log(response.data.sentiment));
```

---

Stay tuned for updates—we’re continuously adding new features and content to the platform. Make sure to [watch this repository](https://github.com/waynecarter/simple-intelligence) to get notified about the latest updates.
