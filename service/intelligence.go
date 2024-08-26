package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

func main() {
	// Load environment variables
	loadEnv()

	// Load configuration
	portStr := os.Getenv("PORT")
	port, err := strconv.Atoi(portStr)
	if err != nil || port == 0 {
		port = 8080
	}

	// Start the service
	http.HandleFunc("/intelligence", intelligenceHandler())
	log.Printf("Server starting on port %d\n", port)
	err = http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
	if err != nil {
		log.Fatalf("Server failed: %s", err)
	}
}

func intelligenceHandler() http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		model := r.URL.Query().Get("model")

		// Get the input parameters
		paramsStr := r.URL.Query().Get("params")
		var params map[string]interface{}
		if paramsStr != "" {
			err := json.Unmarshal([]byte(paramsStr), &params)
			if err != nil {
				http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
				return
			}
		} else {
			err := json.NewDecoder(r.Body).Decode(&params)
			if err != nil {
				http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
				return
			}
		}

		// Generate the intelligence
		intelligence, err := getIntelligence(model, params)
		if err != nil {
			http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusBadRequest)
			return
		}

		// Prepare and send response
		response := make(map[string]interface{})
		if intelligence != nil {
			response[model] = intelligence
		}

		err = json.NewEncoder(w).Encode(response)
		if err != nil {
			http.Error(w, fmt.Sprintf(`{"error":"%s"}`, err.Error()), http.StatusInternalServerError)
		}
	}
}

func getIntelligence(model string, params map[string]interface{}) (interface{}, error) {
	var intelligence interface{}
	var err error

	switch model {
	case "sentiment":
		text, _ := params["text"].(string)
		intelligence, err = getSentiment(text)

	case "classification":
		text, _ := params["text"].(string)
		labels := extractStrings(params["labels"].([]interface{}))
		intelligence, err = getClassification(text, labels)

	case "extraction":
		text, _ := params["text"].(string)
		labels := extractStrings(params["labels"].([]interface{}))
		intelligence, err = getExtraction(text, labels)

	case "corrected_grammar":
		text, _ := params["text"].(string)
		intelligence, err = getCorrectedGrammar(text)

	case "generated_text":
		prompt, _ := params["prompt"].(string)
		maxWords, _ := params["max_words"].(float64)
		intelligence, err = getGeneratedText(prompt, int(maxWords))

	case "masked":
		text, _ := params["text"].(string)
		labels := extractStrings(params["labels"].([]interface{}))
		intelligence, err = getMasked(text, labels)

	case "similarity":
		text1, _ := params["text1"].(string)
		text2, _ := params["text2"].(string)
		intelligence, err = getSimilarity(text1, text2)

	case "summary":
		text, _ := params["text"].(string)
		maxWords, _ := params["max_words"].(float64)
		intelligence, err = getSummary(text, int(maxWords))

	case "translation":
		text, _ := params["text"].(string)
		toLanguage, _ := params["to_language"].(string)
		intelligence, err = getTranslation(text, toLanguage)

	case "embeddings":
		// Convert 'text' to a slice if it's not already one
		var texts []string
		switch text := params["text"].(type) {
		case []string:
			texts = text
		case string:
			texts = []string{text}
		default:
			texts = []string{}
		}
		intelligence, err = getEmbeddings(texts)

	default:
		err = errors.New("model not recognized")
	}

	return intelligence, err
}

func getSentiment(text string) (*string, error) {
	if text == "" {
		return nil, nil
	}

	// Set system and user prompts
	sentimentOptions := []string{"positive", "negative", "neutral", "mixed"}
	systemPrompt := fmt.Sprintf(`
		You are a highly accurate sentiment analysis assistant. Your task is to determine the
		sentiment of the text provided by the user. You must respond with exactly one of the
		following terms: %s, or unknown. Provide no additional text or explanation.
	`, strings.Join(sentimentOptions, ", "))
	userPrompt := text

	// Get completion
	sentiment, err := getCompletion(systemPrompt, userPrompt, 10, 0.5)
	if err != nil {
		return nil, err
	}

	// Filter the sentiment to the valid options
	if !contains(sentimentOptions, sentiment) {
		sentiment = nil
	}

	return sentiment, nil
}

func getClassification(text string, labels []string) (*string, error) {
	if text == "" || len(labels) == 0 {
		return nil, nil
	}

	// Calculate max_tokens by finding the maximum number of words in any label, then add a buffer
	maxTokens := maxWordCount(labels) + 10

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a highly accurate classification assistant. Your task is to categorize the text provided by the user 
		into one of the following classifications: %s. If the text clearly aligns with one of these 
		labels, respond with the exact label. If the text does not clearly match any of the provided labels, respond 
		with 'unknown'. Do not include any additional text or explanation.
	`, strings.Join(labels, ", "))
	userPrompt := text

	// Get completion
	classification, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.5)
	if err != nil {
		return nil, err
	}

	// Filter the classification to the valid labels
	if !contains(labels, classification) {
		classification = nil
	}

	return classification, nil
}

func getExtraction(text string, labels []string) (map[string]string, error) {
	if text == "" || len(labels) == 0 {
		return nil, nil
	}

	// Calculate max tokens as 20 times the number of labels to provide space for 20 tokens per label
	maxTokens := 20 * len(labels)

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a highly accurate entity extraction assistant. Extract specific types of entities from the provided text. 
		The entities to be extracted are: %s. Return the entities in a JSON format with the entity types 
		as keys and the extracted values as values. If an entity is not found, completely omit that entity type from the 
		JSON output. Do not return null or empty values.

		Example 1:
		Text: John Doe lives in New York and works for Acme Corp.
		Entity Types: person, location, organization, time
		Result: {"person": "John Doe", "location": "New York", "organization": "Acme Corp."}

		Example 2:
		Text: Send an email to jane.doe@example.com about the meeting at 10am.
		Entity Types: email, time
		Result: {"email": "jane.doe@example.com", "time": "10am"}`, strings.Join(labels, ", "))
	userPrompt := text

	// Get completion
	extraction, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.5)
	if err != nil {
		return nil, err
	}

	// Parse the JSON string into a map
	var extractionMap map[string]string
	if extraction == nil || *extraction == "" {
		return nil, nil
	}
	err = json.Unmarshal([]byte(*extraction), &extractionMap)
	if err != nil {
		return nil, err
	}

	// Filter the extraction to include only non-empty values that match the labels list
	filteredExtraction := make(map[string]string)
	for _, label := range labels {
		if value, exists := extractionMap[label]; exists && value != "" {
			filteredExtraction[label] = value
		}
	}

	return filteredExtraction, nil
}

func getCorrectedGrammar(text string) (*string, error) {
	if text == "" {
		return nil, nil
	}

	// Calculate max tokens as 150% of the length of the content
	maxTokens := int(1.5 * float64(len(text)))

	// Set system and user prompts
	systemPrompt := `
		You are a highly accurate grammar correction assistant. Your task is to correct the grammar
		in the text provided by the user. Respond with the corrected version of the text only, with
		no additional text or explanation.`
	userPrompt := text

	// Get completion
	correctedGrammar, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.5)
	if err != nil {
		return nil, err
	}

	return correctedGrammar, nil
}

func getGeneratedText(prompt string, maxWords int) (*string, error) {
	if prompt == "" {
		return nil, nil
	}

	// Clamp max words
	if maxWords < 1 {
		maxWords = 50
	}

	// Calculate max tokens as 130% of the max words
	maxTokens := int(1.3 * float64(maxWords))

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a skilled text generation assistant with a strong command of language. Your task is to
		write well-structured, clear, and effective responses based on the user's prompt in %d
		words or less. Ensure the response is relevant and concise. Do not include any emojis unless the
		user explicitly requests them. Always generate responses without leading and trailing quotation
		marks.`, maxWords)
	userPrompt := prompt

	// Get completion
	generatedText, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.7)
	if err != nil {
		return nil, err
	}

	// Even thought it is instructed not to, the model sometimes returns generated text
	// with leading and trailing quotes. If that happens, remove them.
	if generatedText != nil {
		trimmedText := strings.Trim(*generatedText, `"`)
		generatedText = &trimmedText
	}

	return generatedText, nil
}

func getMasked(text string, labels []string) (*string, error) {
	if text == "" {
		return nil, nil
	}
	if len(labels) == 0 {
		return &text, nil
	}

	// Calculate max tokens as 150% of the length of the content
	maxTokens := int(1.5 * float64(len(text)))

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a skilled text processing assistant. Your task is to mask specific types of information in the text 
		provided by the user. The types of information to be masked are: %s. Replace each instance 
		of the specified information with '[MASKED]'. Ensure that only the specified information is masked, and that 
		the rest of the content remains unchanged.`, strings.Join(labels, ", "))
	userPrompt := text

	// Get completion
	masked, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.5)
	if err != nil {
		return nil, err
	}

	return masked, nil
}

func getSimilarity(text1, text2 string) (float64, error) {
	// If both texts are empty, return completely similar (1.0)
	if text1 == "" && text2 == "" {
		return 1.0, nil
	}
	// If one text is empty and the other is not, return no similarity (0.0)
	if text1 == "" || text2 == "" {
		return 0.0, nil
	}

	// Set system and user prompts
	systemPrompt := `
		You are a highly accurate semantic analysis assistant. Your task is to evaluate the semantic similarity between
		two pieces of text provided by the user. Provide a similarity score as a floating-point number between 0 and 1,
		where 1 means the texts are identical in meaning, and 0 means they are completely different. Provide only the
		similarity score as a floating-point number, with no additional text or explanation.`
	userPrompt := fmt.Sprintf(`
		Text 1: %s
		Text 2: %s`, text1, text2)

	// Get completion
	similarityStr, err := getCompletion(systemPrompt, userPrompt, 10, 0.1)
	if err != nil {
		return 0.0, err
	}

	// // Convert the similarity score to a float
	var similarity float64
	if similarityStr != nil {
		trimmedStr := strings.TrimSpace(*similarityStr)
		similarityFloat, err := strconv.ParseFloat(trimmedStr, 64)
		if err != nil {
			return 0.0, err
		}
		similarity = similarityFloat
	} else {
		similarity = 0.0
	}

	return similarity, nil
}

func getSummary(text string, maxWords int) (*string, error) {
	if text == "" {
		return nil, nil
	}

	// Clamp max words
	if maxWords < 1 {
		maxWords = 50
	}

	// Calculate max tokens as 130% of the max words
	maxTokens := int(1.3 * float64(maxWords))

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a highly accurate summarization assistant. Summarize the provided text in %d words or less. Return only
		the summary, with no additional text or explanation.`, maxWords)
	userPrompt := text

	// Get completion
	summary, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.5)
	if err != nil {
		return nil, err
	}

	return summary, nil
}

func getTranslation(text, toLanguage string) (*string, error) {
	if text == "" {
		return nil, nil
	}
	if toLanguage == "" {
		return &text, nil
	}

	// Calculate max tokens as 150% of the length of the content
	maxTokens := int(1.5 * float64(len(text)))

	// Set system and user prompts
	systemPrompt := fmt.Sprintf(`
		You are a highly accurate translation assistant. Translate the provided text to %s. Return only the translated
		text, with no additional explanation.`, toLanguage)
	userPrompt := text

	// Get completion
	translation, err := getCompletion(systemPrompt, userPrompt, maxTokens, 0.1)
	if err != nil {
		return nil, err
	}

	return translation, nil
}

func getCompletion(systemPrompt, userPrompt string, maxTokens int, temperature float32) (*string, error) {
	type ChatCompletionMessage struct {
		Role    string `json:"role"`
		Content string `json:"content"`
	}

	type ChatCompletionRequest struct {
		Model       string                  `json:"model"`
		Messages    []ChatCompletionMessage `json:"messages"`
		MaxTokens   int                     `json:"max_tokens"`
		Temperature float32                 `json:"temperature"`
	}

	type ChatCompletionResponse struct {
		Choices []struct {
			Message struct {
				Content string `json:"content"`
			} `json:"message"`
		} `json:"choices"`
	}

	if systemPrompt == "" && userPrompt == "" {
		return nil, nil
	}

	// Prepare the messages for the API request
	messages := []ChatCompletionMessage{
		{Role: "system", Content: systemPrompt},
		{Role: "user", Content: userPrompt},
	}

	// Create the request body
	requestBody, err := json.Marshal(ChatCompletionRequest{
		Model:       "gpt-4o-mini",
		Messages:    messages,
		MaxTokens:   maxTokens,
		Temperature: temperature,
	})
	if err != nil {
		return nil, err
	}

	// Set up the request
	apiKey := os.Getenv("OPENAI_API_KEY")
	req, err := http.NewRequest("POST", "https://api.openai.com/v1/chat/completions", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	// Execute the request
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Read and parse the response
	var completionResponse ChatCompletionResponse
	if err := json.NewDecoder(resp.Body).Decode(&completionResponse); err != nil {
		return nil, err
	}

	// Check if choices are returned
	if len(completionResponse.Choices) == 0 {
		return nil, nil
	}

	// Extract and return the completion message content
	completion := strings.TrimSpace(completionResponse.Choices[0].Message.Content)
	return &completion, nil
}

func getEmbeddings(texts []string) ([][]float64, error) {
	type EmbeddingRequest struct {
		Model string   `json:"model"`
		Input []string `json:"input"`
	}

	type EmbeddingResponse struct {
		Data []struct {
			Embedding []float64 `json:"embedding"`
		} `json:"data"`
	}

	if len(texts) == 0 {
		return nil, nil
	}

	// Replace newline characters with a space in each text item to create a single line of text per item
	for i, text := range texts {
		texts[i] = strings.ReplaceAll(text, "\n", " ")
	}

	// Create the request body
	requestBody, err := json.Marshal(EmbeddingRequest{
		Model: "text-embedding-ada-002",
		Input: texts,
	})
	if err != nil {
		return nil, err
	}

	// Set up the request
	apiKey := os.Getenv("OPENAI_API_KEY")
	req, err := http.NewRequest("POST", "https://api.openai.com/v1/embeddings", bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+apiKey)

	// Execute the request
	client := &http.Client{}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	// Read the response
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		return nil, err
	}

	// Parse the response JSON
	var embeddingResponse EmbeddingResponse
	err = json.Unmarshal(body, &embeddingResponse)
	if err != nil {
		return nil, err
	}

	// Extract embeddings from the response
	var embeddings [][]float64
	for _, data := range embeddingResponse.Data {
		embeddings = append(embeddings, data.Embedding)
	}

	return embeddings, nil
}

// Helper function to load environment variables from a .env file
func loadEnv() {
	// Define the path to the .env file
	envFilePath := "intelligence.env"

	// Check if the file exists
	if _, err := os.Stat(envFilePath); os.IsNotExist(err) {
		return
	}

	// Open the .env file
	file, err := os.Open(envFilePath)
	if err != nil {
		// Handle error opening the file
		return
	}
	defer file.Close()

	// Read the file line by line
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue // Skip empty lines and comments
		}

		// Split the line into key and value
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue // Skip lines that don't have a key-value pair
		}

		// Set the environment variable
		key := parts[0]
		value := parts[1]
		os.Setenv(key, value)
	}
}

// Helper function to extract a strings array from an interface array
func extractStrings(interfaces []interface{}) []string {
	var strings []string
	for _, raw := range interfaces {
		if str, ok := raw.(string); ok {
			strings = append(strings, str)
		}
	}
	return strings
}

// Helper function to check if a slice contains a given string
func contains(slice []string, item *string) bool {
	if item == nil {
		return false
	}
	for _, s := range slice {
		if s == *item {
			return true
		}
	}
	return false
}

// Helper function to find the maximum word count in the labels
func maxWordCount(items []string) int {
	maxCount := 0
	for _, item := range items {
		wordCount := len(strings.Fields(item))
		if wordCount > maxCount {
			maxCount = wordCount
		}
	}
	return maxCount
}
