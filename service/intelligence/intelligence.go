package intelligence

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"
)

type Intelligence struct {
	config     map[string]Service
	httpClient *http.Client
	mu         sync.RWMutex
}

// Initializes a new Intelligence object loding the configuration from a file
func NewIntelligence(configPath string) (*Intelligence, error) {
	intel := &Intelligence{
		httpClient: &http.Client{
			Timeout: 30 * time.Second,
		},
	}
	if err := intel.loadConfig(configPath); err != nil {
		return nil, err
	}
	return intel, nil
}

// Reads and loads the service configuration from a file
func (i *Intelligence) loadConfig(filePath string) error {
	configBytes, err := os.ReadFile(filePath)
	if err != nil {
		return fmt.Errorf("error reading config file: %v", err)
	}

	var config map[string]Service
	if err := json.Unmarshal(configBytes, &config); err != nil {
		return err
	}

	// Set the service name to match the key in the config
	for key, service := range config {
		service.Name = key
		config[key] = service
	}

	i.mu.Lock()
	i.config = config
	i.mu.Unlock()

	return nil
}

// Defines a service with its parameters and configuration
type Service struct {
	Name        string
	Model       string                 `json:"model"`
	Provider    string                 `json:"provider"`
	Type        string                 `json:"type"`
	Params      map[string]ParamConfig `json:"params"`
	Completions CompletionsConfig      `json:"completions,omitempty"`
	Images      ImagesConfig           `json:"images,omitempty"`
}

// Defines whether a parameter is required and provides default values
type ParamConfig struct {
	Required bool        `json:"required,omitempty"`
	Default  interface{} `json:"default,omitempty"`
}

// Defines settings for the completions API such as max tokens and temperature
type CompletionsConfig struct {
	Messages       []MessageTemplate `json:"messages,omitempty"`
	Temperature    float64           `json:"temperature"`
	MaxTokens      MaxTokens         `json:"max_tokens"`
	ResponseFormat *ResponseFormat   `json:"response_format,omitempty"`
}

// Defines a template message for completion requests
type MessageTemplate struct {
	Role    string   `json:"role"`
	Content []string `json:"content"`
}

// Defines the format for response outputs such as JSON schemas
type ResponseFormat struct {
	Type       string                 `json:"type"`
	JSONSchema map[string]interface{} `json:"json_schema"`
}

// Defines the maximum token count for completions and optional dynamic additions
type MaxTokens struct {
	Value int            `json:"value,omitempty"`
	Add   []MaxTokensAdd `json:"add,omitempty"`
	Min   int            `json:"min,omitempty"`
	Max   int            `json:"max,omitempty"`
}

// Defines how to add tokens dynamically based on parameters
type MaxTokensAdd struct {
	Param    string  `json:"param"`
	Measure  string  `json:"measure"`
	Multiply float64 `json:"multiply,omitempty"`
	Add      int     `json:"add,omitempty"`
}

// Defines image generation requests
type ImagesConfig struct {
	Generations ImagesGenerationsConfig `json:"generations,omitempty"`
}

// Defines the maximum number of generated images
type ImagesGenerationsConfig struct {
	MaxCount int `json:"max_count,omitempty"`
}

// Defines the payload for completion requests
type CompletionsRequest struct {
	Model       string               `json:"model"`
	Messages    []CompletionsMessage `json:"messages"`
	MaxTokens   int                  `json:"max_tokens"`
	Temperature float64              `json:"temperature"`
}

// Defines the message sent to the completions API
type CompletionsMessage struct {
	Role    string      `json:"role"`
	Content interface{} `json:"content"`
}

// Defines the payload for embedding requests
type EmbeddingsRequest struct {
	Model string   `json:"model"`
	Input []string `json:"input"`
}

// Defines the payload for moderation API requests
type ModerationRequest struct {
	Input string `json:"input"`
}

// Defines a file with content and metadata
type Blob struct {
	ContentType string `json:"content_type"`
	Content     []byte `json:"content,omitempty"`
	Base64      string `json:"base64,omitempty"`
}

// Defines a map of Blob objects
type Blobs map[string]*Blob

// Defines a set of named service requests
type Requests map[string]Request

// Defines a map that stores parameters for a single service request
type Request map[string]interface{}

// Defines a map of successful responses from the requests
type Results map[string]interface{}

// Defines a map of errors encountered during request processing
type Errors map[string]string

// Handles incoming intelligence requests based on the specified service model
func (i *Intelligence) GetIntelligence(ctx context.Context, modelName string, params map[string]interface{}) (interface{}, error) {
	i.mu.RLock()
	service, exists := i.config[modelName] // Retrieve the service configuration
	i.mu.RUnlock()
	if !exists {
		return nil, fmt.Errorf("model '%s' not found", modelName)
	}

	// Prepare and validate parameters
	preparedParams, err := i.prepareParams(service, params)
	if err != nil {
		return nil, err
	}

	// Call the appropriate service based on its type
	var result interface{}
	switch service.Type {
	case "v1/completions":
		result, err = i.getCompletion(ctx, service, preparedParams)
	case "v1/embeddings":
		result, err = i.getEmbeddings(ctx, service, preparedParams)
	case "v1/moderations":
		result, err = i.getModeration(ctx, service, preparedParams)
	case "v1/images/generations":
		result, err = i.getImageGenerations(ctx, service, preparedParams)
	default:
		err = fmt.Errorf("unsupported service type: %s", service.Type)
	}

	if err == nil {
		// Attempt to parse the result as JSON if it's a string
		switch v := result.(type) {
		case string:
			var parsedResult interface{}
			if err := json.Unmarshal([]byte(v), &parsedResult); err == nil {
				result = parsedResult
			}
		case *string:
			if v != nil {
				var parsedResult interface{}
				if err := json.Unmarshal([]byte(*v), &parsedResult); err == nil {
					result = parsedResult
				}
			}
		}
	}

	return result, err
}

// Validates and applies default values to parameters
func (i *Intelligence) prepareParams(service Service, params map[string]interface{}) (map[string]interface{}, error) {
	filteredParams := make(map[string]interface{})

	// Iterate over each parameter and validate required ones, applying defaults where necessary
	for paramName, paramConfig := range service.Params {
		value, exists := params[paramName]

		if paramConfig.Required && !exists {
			return nil, fmt.Errorf("required parameter '%s' is missing", paramName)
		}

		if !exists && paramConfig.Default != nil {
			filteredParams[paramName] = paramConfig.Default
		} else if exists {
			filteredParams[paramName] = value
		}
	}

	return filteredParams, nil
}

// Sends a completions request and returns the result
func (i *Intelligence) getCompletion(ctx context.Context, service Service, params map[string]interface{}) (*string, error) {
	var messages []CompletionsMessage
	// Prepare messages by replacing parameter placeholders
	for _, message := range service.Completions.Messages {
		content := strings.Join(message.Content, "\n")
		for key, value := range params {
			switch v := value.(type) {
			case []interface{}:
				joinedValue := strings.Join(convertToStringSlice(v), ", ")
				content = strings.ReplaceAll(content, fmt.Sprintf("{{params.%s}}", key), joinedValue)
			default:
				content = strings.ReplaceAll(content, fmt.Sprintf("{{params.%s}}", key), fmt.Sprintf("%v", value))
			}
		}
		messages = append(messages, CompletionsMessage{Role: message.Role, Content: content})
	}

	// Add any blob content to the messages
	addBlobsToMessages(params, &messages)

	// Prepare the request body with model, messages, and other configuration
	requestBodyMap := map[string]interface{}{
		"model":       service.Model,
		"messages":    messages,
		"max_tokens":  i.calculateMaxTokens(service.Completions.MaxTokens, params),
		"temperature": service.Completions.Temperature,
	}
	if responseFormat := i.getServiceResponseFormat(service, params); responseFormat != nil {
		requestBodyMap["response_format"] = responseFormat
	}

	requestBody, err := json.Marshal(requestBodyMap)
	if err != nil {
		return nil, err
	}

	response, err := i.doServiceRequest(ctx, service, requestBody)
	if err != nil {
		return nil, err
	}

	// Extract and return the completion content from the response
	if choices, ok := response["choices"].([]interface{}); ok && len(choices) > 0 {
		if choice, ok := choices[0].(map[string]interface{}); ok {
			if message, ok := choice["message"].(map[string]interface{}); ok {
				if content, ok := message["content"].(string); ok {
					return &content, nil
				}
			}
		}
	}

	return nil, fmt.Errorf("no valid completion response found")
}

// Recursively adds any Blob content to the messages
func addBlobsToMessages(value interface{}, messages *[]CompletionsMessage) {
	switch v := value.(type) {
	case []interface{}:
		for i := 0; i < len(v); i++ {
			addBlobsToMessages(v[i], messages)
		}
	case Blob:
		addBlobToMessages(v, messages)
	case map[string]interface{}:
		addBlobToMessages(v, messages)
		for _, nestedValue := range v {
			addBlobsToMessages(nestedValue, messages)
		}
	default:
		return
	}
}

// Appends a Blob content message to the list of messages
func addBlobToMessages(value interface{}, messages *[]CompletionsMessage) {
	var base64Content, contentType string

	switch blob := value.(type) {
	case Blob:
		if len(blob.Content) > 0 {
			base64Content = base64.StdEncoding.EncodeToString(blob.Content)
		} else {
			base64Content = blob.Base64
		}
		contentType = blob.ContentType
	case map[string]interface{}:
		if ct, ok := blob["content_type"].(string); ok {
			contentType = ct
		}
		if b64, ok := blob["base64"].(string); ok {
			base64Content = b64
		}
	}

	if contentType != "" && base64Content != "" {
		message := createBlobCompletionsMessage(base64Content, contentType)
		*messages = append(*messages, message)
	}
}

// Creates a completion message for a Blob
func createBlobCompletionsMessage(base64 string, contentType string) CompletionsMessage {
	url := fmt.Sprintf("data:%s;base64,%s", contentType, base64)
	return CompletionsMessage{
		Role: "user",
		Content: []interface{}{
			map[string]interface{}{
				"type":      "image_url",
				"image_url": map[string]interface{}{"url": url},
			},
		},
	}
}

// Sends an embeddings request and returns the result
func (i *Intelligence) getEmbeddings(ctx context.Context, service Service, params map[string]interface{}) ([][]float64, error) {
	// Extract input texts parameter
	inputsInterface, ok := params["texts"].([]interface{})
	if !ok || len(inputsInterface) == 0 {
		return nil, fmt.Errorf("invalid input: 'texts' parameter is required")
	}

	// Convert input interfaces to strings
	inputs := convertToStringSlice(inputsInterface)

	// Prepare the request body
	requestBody, err := json.Marshal(EmbeddingsRequest{
		Model: service.Model,
		Input: inputs,
	})
	if err != nil {
		return nil, err
	}

	response, err := i.doServiceRequest(ctx, service, requestBody)
	if err != nil {
		return nil, err
	}

	// Extract the embeddings from the response
	data, ok := response["data"].([]interface{})
	if !ok {
		return nil, fmt.Errorf("invalid embeddings response format")
	}

	// Convert embedding data to [][]float64
	var embeddings [][]float64
	for _, item := range data {
		itemMap, ok := item.(map[string]interface{})
		if !ok {
			return nil, fmt.Errorf("invalid embeddings data format")
		}
		embeddingInterface, ok := itemMap["embedding"].([]interface{})
		if !ok {
			return nil, fmt.Errorf("missing 'embedding' in data item")
		}
		var embedding []float64
		for _, val := range embeddingInterface {
			if num, ok := val.(float64); ok {
				embedding = append(embedding, num)
			} else {
				return nil, fmt.Errorf("embedding values must be float64")
			}
		}
		embeddings = append(embeddings, embedding)
	}

	return embeddings, nil
}

// Sends a moderation request and returns the result
func (i *Intelligence) getModeration(ctx context.Context, service Service, params map[string]interface{}) (map[string]interface{}, error) {
	input, ok := params["text"].(string)
	if !ok || input == "" {
		return nil, fmt.Errorf("invalid input: 'text' parameter is required")
	}

	// Prepare the request body
	requestBody, err := json.Marshal(ModerationRequest{
		Input: input,
	})
	if err != nil {
		return nil, err
	}

	// Send the request and process the response
	response, err := i.doServiceRequest(ctx, service, requestBody)
	if err != nil {
		return nil, err
	}

	// Define a struct to unmarshal the moderation response
	type ModerationResponse struct {
		Results []struct {
			Flagged    bool `json:"flagged"`
			Categories struct {
				Sexual                bool `json:"sexual"`
				Hate                  bool `json:"hate"`
				Harassment            bool `json:"harassment"`
				SelfHarm              bool `json:"self-harm"`
				SexualMinors          bool `json:"sexual/minors"`
				HateThreatening       bool `json:"hate/threatening"`
				ViolenceGraphic       bool `json:"violence/graphic"`
				SelfHarmIntent        bool `json:"self-harm/intent"`
				SelfHarmInstructions  bool `json:"self-harm/instructions"`
				HarassmentThreatening bool `json:"harassment/threatening"`
				Violence              bool `json:"violence"`
			} `json:"categories"`
			CategoryScores map[string]float64 `json:"category_scores"`
		} `json:"results"`
	}

	var moderationResponse ModerationResponse
	responseBody, _ := json.Marshal(response)
	if err := json.Unmarshal(responseBody, &moderationResponse); err != nil {
		return nil, err
	}

	// Return the first moderation result
	if len(moderationResponse.Results) == 0 {
		return nil, fmt.Errorf("no results found in moderation response")
	}

	result := moderationResponse.Results[0]
	moderation := map[string]interface{}{
		"flagged":         result.Flagged,
		"categories":      result.Categories,
		"category_scores": result.CategoryScores,
	}

	return moderation, nil
}

// Calculates the maximum number of tokens for a request
func (i *Intelligence) calculateMaxTokens(maxTokensConfig MaxTokens, params map[string]interface{}) int {
	maxTokens := maxTokensConfig.Value

	// Add dynamic token values based on parameter configuration
	for _, paramConfig := range maxTokensConfig.Add {
		maxTokens += i.calculateTokensForParam(paramConfig, params)
	}

	// Apply min and max limits to the token count
	if maxTokensConfig.Min > 0 && maxTokens < maxTokensConfig.Min {
		maxTokens = maxTokensConfig.Min
	}
	if maxTokensConfig.Max > 0 && maxTokens > maxTokensConfig.Max {
		maxTokens = maxTokensConfig.Max
	}

	return maxTokens
}

// Calculates token counts for a single parameter
func (i *Intelligence) calculateTokensForParam(addConfig MaxTokensAdd, params map[string]interface{}) int {
	var value int
	paramValue, ok := params[addConfig.Param]
	if !ok {
		return 0
	}

	// Calculate token count based on the measure type
	switch addConfig.Measure {
	case "length":
		value = getParamLength(paramValue)
	case "sum_item_length":
		value = sumParamItemLengths(paramValue)
	case "max_item_length":
		value = maxParamItemLength(paramValue)
	default:
		value = getParamValueAsInt(paramValue)
	}

	// Apply multiplier and additional tokens
	if addConfig.Multiply > 0 {
		value = int(float64(value) * addConfig.Multiply)
	}
	value += addConfig.Add

	return value
}

// Sends an image generation request and returns the result
func (i *Intelligence) getImageGenerations(ctx context.Context, service Service, params map[string]interface{}) (*Blob, error) {
	// Extract the prompt parameter
	prompt, ok := params["prompt"].(string)
	if !ok || prompt == "" {
		return nil, fmt.Errorf("invalid input: 'prompt' parameter is required")
	}

	// Build the request body with optional parameters for size, quality, and style
	requestBodyMap := map[string]interface{}{
		"model":           service.Model,
		"prompt":          prompt,
		"response_format": "b64_json",
	}

	optionalParams := []string{"size", "quality", "style"}
	for _, param := range optionalParams {
		if val, ok := params[param].(string); ok && val != "" {
			requestBodyMap[param] = val
		}
	}

	// Marshal request body and send request
	requestBody, err := json.Marshal(requestBodyMap)
	if err != nil {
		return nil, err
	}

	response, err := i.doServiceRequest(ctx, service, requestBody)
	if err != nil {
		return nil, err
	}

	// Extract the image data from the response
	if data, ok := response["data"].([]interface{}); ok && len(data) > 0 {
		for _, item := range data {
			if imageMap, ok := item.(map[string]interface{}); ok {
				if base64Image, ok := imageMap["b64_json"].(string); ok {
					return &Blob{
						ContentType: "image/png",
						Base64:      base64Image,
					}, nil
				}
			}
		}
	}

	return nil, fmt.Errorf("no results found in image generation response")
}

// Sends an HTTP request to the specified service and returns the response
func (i *Intelligence) doServiceRequest(ctx context.Context, service Service, requestBody []byte) (map[string]interface{}, error) {
	url, err := i.getServiceURL(service)
	if err != nil {
		return nil, err
	}

	// Prepare and send the HTTP request
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, url, bytes.NewBuffer(requestBody))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")

	if err := i.addServiceHeaders(service, req); err != nil {
		return nil, err
	}

	resp, err := i.httpClient.Do(req)
	if err != nil {
		return nil, fmt.Errorf("error making request to '%s' service: %v", service.Name, err)
	}
	defer resp.Body.Close()

	// Check the response status and handle errors
	if resp.StatusCode != http.StatusOK {
		var errorMessage string
		if bodyBytes, err := io.ReadAll(resp.Body); err == nil {
			// Default the error message to the body contents
			errorMessage = string(bodyBytes)

			// If the body contents are a map, try to extract the error message
			var bodyMap map[string]interface{}
			if err := json.Unmarshal(bodyBytes, &bodyMap); err == nil {
				if errorMap, ok := bodyMap["error"].(map[string]interface{}); ok {
					if errorMsg, ok := errorMap["message"].(string); ok {
						errorMessage = fmt.Sprintf("error from '%s' service: %v", service.Name, errorMsg)
					}
				}
			}
		} else {
			errorMessage = fmt.Sprintf("error from '%s' service", service.Name)
		}
		return nil, errors.New(errorMessage)
	}

	// Parse and return the response
	var responseMap map[string]interface{}
	if err := json.NewDecoder(resp.Body).Decode(&responseMap); err != nil {
		return nil, fmt.Errorf("error decoding response from '%s' service: %v", service.Name, err)
	}

	return responseMap, nil
}

// Returns the API URL based on the service provider and type
func (i *Intelligence) getServiceURL(service Service) (string, error) {
	switch service.Provider {
	case "openai":
		switch service.Type {
		case "v1/completions":
			return "https://api.openai.com/v1/chat/completions", nil
		case "v1/embeddings":
			return "https://api.openai.com/v1/embeddings", nil
		case "v1/moderations":
			return "https://api.openai.com/v1/moderations", nil
		case "v1/images/generations":
			return "https://api.openai.com/v1/images/generations", nil
		default:
			return "", fmt.Errorf("unsupported service type: %s", service.Type)
		}
	default:
		return "", fmt.Errorf("unsupported service provider: %s", service.Provider)
	}
}

// Adds necessary headers (such as API keys) for the service request
func (i *Intelligence) addServiceHeaders(service Service, req *http.Request) error {
	switch service.Provider {
	case "openai":
		apiKey := os.Getenv("OPENAI_API_KEY")
		if apiKey == "" {
			return fmt.Errorf("OPENAI_API_KEY environment variable not set")
		}
		req.Header.Set("Authorization", fmt.Sprintf("Bearer %s", apiKey))
		return nil
	default:
		return fmt.Errorf("no API key for provider: %s", service.Provider)
	}
}

// Returns the expanded response format based on parameters
func (i *Intelligence) getServiceResponseFormat(service Service, params map[string]interface{}) *ResponseFormat {
	responseFormat := service.Completions.ResponseFormat
	if responseFormat == nil || responseFormat.JSONSchema == nil {
		return nil
	}

	// Expand the schema using the provided parameters
	expandedSchema := deepCopyObject(responseFormat.JSONSchema).(map[string]interface{})
	expandedSchema = expandObject(expandedSchema, params).(map[string]interface{})
	newResponseFormat := *responseFormat
	newResponseFormat.JSONSchema = expandedSchema
	return &newResponseFormat
}

// Request Handling

// Processes incoming intelligence requests
func (i *Intelligence) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctx := r.Context()

		// Parse the incoming request to extract intelligence requests
		requests, err := getRequests(r)
		if err != nil {
			http.Error(w, fmt.Sprintf(`{"errors": {"request": "failed to read requests: %s"}}`, err.Error()), http.StatusBadRequest)
			return
		}

		// Process the requests and collect results/errors
		results, errors := i.doRequests(ctx, requests)

		// If there are errors, include them in the response and set status to BadRequest
		if len(errors) > 0 {
			results["errors"] = errors
			w.WriteHeader(http.StatusBadRequest)
			if err := json.NewEncoder(w).Encode(results); err != nil {
				http.Error(w, fmt.Sprintf(`{"errors": {"server": "failed to write errors: %s"}}`, err.Error()), http.StatusInternalServerError)
			}
			return
		}

		// Write the successful results back as a JSON response
		if err := json.NewEncoder(w).Encode(results); err != nil {
			http.Error(w, fmt.Sprintf(`{"errors": {"server": "failed to write results: %s"}}`, err.Error()), http.StatusInternalServerError)
		}
	})
}

// Parses the incoming HTTP request to extract intelligence requests from either the body or multipart form data
func getRequests(r *http.Request) (Requests, error) {
	contentType := r.Header.Get("Content-Type")
	requests := Requests{}
	files := make(map[string]interface{})
	var err error

	// Handle multipart form data (used for file uploads)
	if strings.HasPrefix(contentType, "multipart/form-data") {
		err = r.ParseMultipartForm(50 << 20) // Limit size to 50MB
		if err != nil {
			return nil, fmt.Errorf("failed to parse multipart form: %v", err)
		}

		// Process file parts from the multipart form
		for partName, fileHeaders := range r.MultipartForm.File {
			for _, fileHeader := range fileHeaders {
				file, err := fileHeader.Open()
				if err != nil {
					return nil, fmt.Errorf("failed to open file '%s': %v", fileHeader.Filename, err)
				}

				fileData, err := io.ReadAll(file)
				file.Close()
				if err != nil {
					return nil, fmt.Errorf("failed to read file '%s': %v", fileHeader.Filename, err)
				}

				// If the part is the "request", treat it as the main body
				if partName == "request" {
					if requests, err = requestsFromData(r, fileData); err != nil {
						return nil, fmt.Errorf("failed to extract request: %v", err)
					}
					continue
				}

				// Handle files as blobs
				blob := Blob{
					ContentType: fileHeader.Header.Get("Content-Type"),
					Content:     fileData,
				}
				files[partName] = blob
			}
		}

		// Process form field values and assign to requests map
		for partName, values := range r.MultipartForm.Value {
			for _, value := range values {
				addToRequests(&requests, partName, value)
			}
		}
	} else {
		// Handle non-multipart requests (typically JSON body)
		body, err := io.ReadAll(r.Body)
		if err != nil {
			return nil, fmt.Errorf("failed to read request body: %v", err)
		}
		requests, err = requestsFromData(r, body)
		if err != nil {
			return nil, fmt.Errorf("failed to extract request: %v", err)
		}
	}

	// Attach files as blobs to the requests
	for key, value := range files {
		addToRequests(&requests, key, value)
	}

	return requests, nil
}

// Parses the request body as either a batch of requests or a single request
func requestsFromData(r *http.Request, data []byte) (Requests, error) {
	var requests Requests

	// Try to unmarshal as a batch of requests
	if err := json.Unmarshal(data, &requests); err != nil {
		// If batch fails, try unmarshaling as a single request
		var single Request
		if err := json.Unmarshal(data, &single); err != nil {
			return nil, err
		}

		// Extract model from query params if not present in the body
		model, exists := single["model"].(string)
		if !exists {
			model = r.URL.Query().Get("model")
		}

		if model == "" {
			return nil, fmt.Errorf("invalid input: 'model' parameter is required")
		}

		// Assign the single request under the model name
		requests = Requests{model: single}
	}

	// Ensure each request has a "model" entry
	for key, request := range requests {
		if _, exists := request["model"].(string); !exists {
			request["model"] = key
		}
	}

	return requests, nil
}

// Adds a value to the Requests map using dot notation for nested fields
func addToRequests(requests *Requests, key string, value interface{}) {
	keys := strings.Split(key, ".")

	// Start with the root request object
	var currentRequest map[string]interface{}
	rootKey := keys[0]
	if _, exists := (*requests)[rootKey]; exists {
		currentRequest = (*requests)[rootKey]
	} else if len(*requests) == 1 {
		for _, req := range *requests {
			currentRequest = req
			break
		}
	} else {
		return
	}

	// Traverse the keys and build nested maps as needed
	for i := 1; i < len(keys)-1; i++ {
		currentKey := keys[i]
		if existingValue, exists := currentRequest[currentKey]; exists {
			if nextRequest, ok := existingValue.(map[string]interface{}); ok {
				currentRequest = nextRequest
			} else {
				currentRequest[currentKey] = []interface{}{existingValue}
			}
		} else {
			currentRequest[currentKey] = make(map[string]interface{})
			currentRequest = currentRequest[currentKey].(map[string]interface{})
		}
	}

	// Assign the final value to the last key
	lastKey := keys[len(keys)-1]
	if existingValue, exists := currentRequest[lastKey]; exists {
		if existingArray, ok := existingValue.([]interface{}); ok {
			currentRequest[lastKey] = append(existingArray, value)
		} else {
			currentRequest[lastKey] = []interface{}{existingValue, value}
		}
	} else {
		currentRequest[lastKey] = value
	}
}

// Processes multiple intelligence requests concurrently and returns the results and errors
func (i *Intelligence) doRequests(ctx context.Context, requests Requests) (Results, Errors) {
	results := make(chan struct {
		key    string
		result interface{}
		err    error
	}, len(requests))

	var wg sync.WaitGroup

	// Process each request concurrently
	for key, request := range requests {
		wg.Add(1)
		go func(key string, request Request) {
			defer wg.Done()

			var result interface{}
			var err error

			// Fetch the model and process the intelligence request
			if model, exists := request["model"].(string); exists {
				result, err = i.GetIntelligence(ctx, model, request)
			} else {
				err = fmt.Errorf("invalid input: 'model' parameter is required")
			}

			// Send the result and error to the results channel
			results <- struct {
				key    string
				result interface{}
				err    error
			}{key: key, result: result, err: err}
		}(key, request)
	}

	// Close the results channel once all requests are processed
	go func() {
		wg.Wait()
		close(results)
	}()

	// Collect the results and errors from the channel
	result := make(Results)
	errors := make(Errors)
	for res := range results {
		if res.err != nil {
			errors[res.key] = res.err.Error()
		} else {
			result[res.key] = res.result
		}
	}

	return result, errors
}

// Utility Functions

// Creates a deep copy of the provided object
func deepCopyObject(src interface{}) interface{} {
	switch v := src.(type) {
	case map[string]interface{}:
		dst := make(map[string]interface{})
		for k, v2 := range v {
			dst[k] = deepCopyObject(v2)
		}
		return dst
	case []interface{}:
		dst := make([]interface{}, len(v))
		for i, v2 := range v {
			dst[i] = deepCopyObject(v2)
		}
		return dst
	default:
		return v
	}
}

// Recursively expands placeholders in the object using the provided parameters
func expandObject(object interface{}, params map[string]interface{}) interface{} {
	switch obj := object.(type) {
	case map[string]interface{}:
		expanded := make(map[string]interface{})
		for key, value := range obj {
			expandedKey := expandPlaceholders(key, params) // Expand keys with placeholders
			expandedValue := expandObject(value, params)   // Expand values with placeholders
			expanded[expandedKey] = expandedValue
		}
		return expanded
	case []interface{}:
		expanded := make([]interface{}, len(obj))
		for i, value := range obj {
			expanded[i] = expandObject(value, params) // Recursively expand arrays
		}
		return expanded
	case string:
		return expandPlaceholders(obj, params) // Expand strings with placeholders
	default:
		return obj
	}
}

// Replaces placeholders in the string with actual parameter values
func expandPlaceholders(value string, params map[string]interface{}) string {
	for key, param := range params {
		placeholder := fmt.Sprintf("{{params.%s}}", key)
		value = strings.ReplaceAll(value, placeholder, fmt.Sprintf("%v", param))
	}
	return value
}

// Converts a slice of interfaces to strings
func convertToStringSlice(arr []interface{}) []string {
	strSlice := make([]string, len(arr))
	for i, v := range arr {
		strSlice[i] = fmt.Sprintf("%v", v)
	}
	return strSlice
}

// Gets the length of a parameter value
func getParamLength(paramValue interface{}) int {
	switch v := paramValue.(type) {
	case string:
		return len(v)
	case []interface{}:
		return len(v)
	default:
		return 0
	}
}

// Sums the lengths of items in an array parameter
func sumParamItemLengths(paramValue interface{}) int {
	sum := 0
	if arr, ok := paramValue.([]interface{}); ok {
		for _, item := range arr {
			sum += len(fmt.Sprintf("%v", item))
		}
	}
	return sum
}

// Gets the maximum length of items in an array parameter
func maxParamItemLength(paramValue interface{}) int {
	maxLength := 0
	if arr, ok := paramValue.([]interface{}); ok {
		for _, item := range arr {
			length := len(fmt.Sprintf("%v", item))
			if length > maxLength {
				maxLength = length
			}
		}
	}
	return maxLength
}

// Gets the parameter value as an integer
func getParamValueAsInt(paramValue interface{}) int {
	switch v := paramValue.(type) {
	case float64:
		return int(v)
	case int:
		return v
	default:
		return 0
	}
}
