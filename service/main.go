package main

import (
	"bufio"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"

	"intelligence/graphql"
	"intelligence/intelligence"
)

// Starts the server by loading environment variables, initializing services, and starting the HTTP server
func main() {
	// Load environment variables
	loadEnv()

	// Get the server port from the environment, default to 8080 if not set or invalid
	portStr := os.Getenv("PORT")
	port, err := strconv.Atoi(portStr)
	if err != nil || port == 0 {
		port = 8080
	}

	// Initialize the intelligence service by loading configuration
	intelligence, err := intelligence.NewIntelligence("intelligence.json")
	if err != nil {
		log.Fatalf("Intelligence failed to load: %s", err)
	}

	// Initialize the GraphQL handler with the loaded intelligence service
	graphQLHandler, err := graphql.NewGraphQLHandler("intelligence.graphql", intelligence)
	if err != nil {
		log.Fatalf("GraphQL handler failed to load: %s", err)
	}

	// Set up the HTTP handlers for GraphQL and intelligence routes
	http.Handle("/graphql", graphQLHandler.Handler())
	http.Handle("/intelligence", intelligence.Handler())

	// Start the HTTP server on the specified port
	log.Printf("Server starting on port %d\n", port)
	err = http.ListenAndServe(fmt.Sprintf(":%d", port), nil)
	if err != nil {
		log.Fatalf("Server failed: %s", err)
	}
}

// Loads environment variables from the specified .env file
func loadEnv() {
	filePath := "intelligence.env"

	// Open the .env file, return if the file does not exist
	file, err := os.Open(filePath)
	if err != nil {
		return
	}
	defer file.Close()

	// Read and process the file line by line
	scanner := bufio.NewScanner(file)
	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())
		// Skip empty lines and lines starting with a comment
		if len(line) == 0 || strings.HasPrefix(line, "#") {
			continue
		}

		// Split the line into key and value at the first '='
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue // Skip invalid lines that don't contain a key-value pair
		}

		// Set the key-value pair as an environment variable
		key := parts[0]
		value := parts[1]
		os.Setenv(key, value)
	}
}
