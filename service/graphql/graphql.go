package graphql

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "os"

    "github.com/graphql-go/graphql"
    "github.com/graphql-go/graphql/language/ast"
    "github.com/graphql-go/graphql/language/parser"
    "github.com/graphql-go/graphql/language/source"

    "intelligence/intelligence"
)

type GraphQLHandler struct {
    schema              *graphql.Schema
    intelligenceService *intelligence.Intelligence
}

// Initializes a new GraphQL handler by loading the schema and setting up the intelligence service
func NewGraphQLHandler(schemaFilePath string, intelligenceService *intelligence.Intelligence) (*GraphQLHandler, error) {
    handler := &GraphQLHandler{
        intelligenceService: intelligenceService,
    }
    // Load and parse the GraphQL schema from the provided file path
    if err := handler.loadSchema(schemaFilePath); err != nil {
        return nil, fmt.Errorf("error loading schema: %v", err)
    }
    return handler, nil
}

// Reads and parses the GraphQL schema from a file and constructs the schema object
func (h *GraphQLHandler) loadSchema(filePath string) error {
    schemaBytes, err := os.ReadFile(filePath)
    if err != nil {
        log.Fatalf("error reading schema file: %v", err)
    }
    schemaSrc := source.NewSource(&source.Source{
        Body: schemaBytes,
    })
    document, err := parser.Parse(parser.ParseParams{Source: schemaSrc})
    if err != nil {
        log.Fatalf("error parsing schema: %v", err)
    }
    // Create GraphQL schema from parsed AST document
    h.schema, err = h.createSchemaFromAST(document)
    if err != nil {
        log.Fatalf("error creating schema: %v", err)
    }
    return nil
}

// Creates a GraphQL schema from the parsed AST document
func (h *GraphQLHandler) createSchemaFromAST(document *ast.Document) (*graphql.Schema, error) {
    typeDefs := make(map[string]*ast.ObjectDefinition)
    var queryTypeName string

    // Gather type definitions and identify the query type
    for _, definition := range document.Definitions {
        if typeDef, ok := definition.(*ast.ObjectDefinition); ok {
            typeDefs[typeDef.Name.Value] = typeDef
        } else if schemaDef, ok := definition.(*ast.SchemaDefinition); ok {
            for _, opType := range schemaDef.OperationTypes {
                if opType.Operation == "query" {
                    queryTypeName = opType.Type.Name.Value
                    break
                }
            }
        }
    }

    // Ensure the schema defines a query type
    if queryTypeName == "" {
        return nil, fmt.Errorf("no query found in the schema")
    }

    // Initialize maps for custom object and input types
    customObjectTypes := make(map[string]*graphql.Object)
    customInputObjectTypes := make(map[string]*graphql.InputObject)
    isInputObjectTypeCache := make(map[string]bool)

    // Build both input and output object types based on schema
    for typeName, typeDef := range typeDefs {
        isInputType := isInputObjectType(typeDef, typeDefs, isInputObjectTypeCache)
        if isInputType {
            customInputObjectTypes[typeName] = graphql.NewInputObject(graphql.InputObjectConfig{
                Name:   typeName,
                Fields: graphql.InputObjectConfigFieldMap{},
            })
        } else {
            customObjectTypes[typeName] = graphql.NewObject(graphql.ObjectConfig{
                Name:   typeName,
                Fields: graphql.Fields{},
            })
        }
    }

    // Populate fields for each object type
    for typeName, typeDef := range typeDefs {
        if customObjectType, exists := customObjectTypes[typeName]; exists {
            var resolver graphql.FieldResolveFn
            if typeName == queryTypeName {
                // Set resolver for the query type
                resolver = h.intelligenceResolver
            }
            fields := h.createFieldsFromObjectDefinition(typeDef, customObjectTypes, customInputObjectTypes, resolver)
            for fieldName, field := range fields {
                customObjectType.AddFieldConfig(fieldName, field)
            }
        }
        if customInputObjectType, exists := customInputObjectTypes[typeName]; exists {
            // Create input object fields
            inputFields := h.createInputFieldsFromObjectDefinition(typeDef, customInputObjectTypes)
            for fieldName, field := range inputFields {
                customInputObjectType.AddFieldConfig(fieldName, field)
            }
        }
    }

    // Ensure we have a valid query object to create the schema
    var query *graphql.Object
    if queryObject, exists := customObjectTypes[queryTypeName]; exists {
        query = queryObject
    }
    if query == nil {
        return nil, fmt.Errorf("no query found in the schema")
    }

    // Construct and return the final schema
    schemaConfig := graphql.SchemaConfig{Query: query}
    schema, err := graphql.NewSchema(schemaConfig)
    if err != nil {
        return nil, fmt.Errorf("failed to create schema: %w", err)
    }

    return &schema, nil
}

// Determines if a type is used as an input type by checking arguments across the schema
func isInputObjectType(typeDef *ast.ObjectDefinition, typeDefs map[string]*ast.ObjectDefinition, cache map[string]bool) bool {
    var isMatchingType func(fieldType ast.Type, typeName string) bool
    isMatchingType = func(fieldType ast.Type, typeName string) bool {
        if cachedResult, exists := cache[typeName]; exists {
            return cachedResult
        }

        switch fieldType := fieldType.(type) {
        case *ast.Named:
            return fieldType.Name.Value == typeName
        case *ast.List:
            return isMatchingType(fieldType.Type, typeName)
        case *ast.NonNull:
            return isMatchingType(fieldType.Type, typeName)
        default:
            return false
        }
    }

    // Check if the type is used in any field's arguments
    for _, otherTypeDef := range typeDefs {
        for _, field := range otherTypeDef.Fields {
            for _, arg := range field.Arguments {
                if isMatchingType(arg.Type, typeDef.Name.Value) {
                    cache[typeDef.Name.Value] = true
                    return true
                }
            }
        }
    }

    cache[typeDef.Name.Value] = false
    return false
}

// Creates the fields for an object definition and maps schema types to GraphQL types
func (h *GraphQLHandler) createFieldsFromObjectDefinition(typeDef *ast.ObjectDefinition, customObjectTypes map[string]*graphql.Object, customInputObjectTypes map[string]*graphql.InputObject, resolver graphql.FieldResolveFn) graphql.Fields {
    fields := graphql.Fields{}

    for _, field := range typeDef.Fields {
        fieldName := field.Name.Value
        fieldType := field.Type

        // Define field and its type, setting up resolver and arguments
        graphqlField := &graphql.Field{
            Name:    fieldName,
            Type:    h.mapSchemaTypeToGraphQLType(fieldType, customObjectTypes, customInputObjectTypes),
            Resolve: resolver,
            Args:    h.createArgumentsConfig(field.Arguments, customObjectTypes, customInputObjectTypes),
        }

        fields[fieldName] = graphqlField
    }

    return fields
}

// Creates input fields for an object definition
func (h *GraphQLHandler) createInputFieldsFromObjectDefinition(typeDef *ast.ObjectDefinition, customInputObjectTypes map[string]*graphql.InputObject) graphql.InputObjectConfigFieldMap {
    fields := graphql.InputObjectConfigFieldMap{}

    for _, field := range typeDef.Fields {
        fieldName := field.Name.Value
        fieldType := field.Type

        // Map input schema type to GraphQL input type
        fields[fieldName] = &graphql.InputObjectFieldConfig{
            Type: h.mapSchemaTypeToGraphQLType(fieldType, nil, customInputObjectTypes),
        }
    }

    return fields
}

// Resolves queries related to intelligence services
func (h *GraphQLHandler) intelligenceResolver(p graphql.ResolveParams) (interface{}, error) {
    type result struct {
        data interface{}
        err  error
    }
    ch := make(chan *result, 1)

    ctx := p.Context

    // Execute the resolver logic asynchronously
    go func() {
        params := make(map[string]interface{})
        for argName, argValue := range p.Args {
            paramName := camelToUnderscore(argName)
            params[paramName] = camelToUnderscoreRecursive(argValue)
        }
        serviceName := camelToUnderscore(p.Info.FieldName)
        if intelligence, err := h.intelligenceService.GetIntelligence(ctx, serviceName, params); err == nil {
            transformedResult := underscoreToCamelCaseRecursive(intelligence)
            ch <- &result{data: transformedResult, err: err}
        } else {
            ch <- &result{data: nil, err: err}
        }
    }()

    // Return a thunk that waits for the result, allowing parallel execution
    return func() (interface{}, error) {
        r := <-ch
        return r.data, r.err
    }, nil
}

// Maps AST schema types to GraphQL types, handling non-nullable, named, and list types
func (h *GraphQLHandler) mapSchemaTypeToGraphQLType(fieldType ast.Type, customObjectTypes map[string]*graphql.Object, customInputObjectTypes map[string]*graphql.InputObject) graphql.Type {
    switch fieldType := fieldType.(type) {
    case *ast.NonNull:
        // Handle non-nullable types
        return graphql.NewNonNull(h.mapSchemaTypeToGraphQLType(fieldType.Type, customObjectTypes, customInputObjectTypes))
    case *ast.Named:
        switch fieldType.Name.Value {
        case "String":
            return graphql.String
        case "Int":
            return graphql.Int
        case "Float":
            return graphql.Float
        case "Boolean":
            return graphql.Boolean
        case "ID":
            return graphql.ID
        case "JSON":
            return jsonScalar
        default:
            // Resolve custom object types
            if objDef, ok := customObjectTypes[fieldType.Name.Value]; ok {
                return objDef
            }
            if inputObjDef, ok := customInputObjectTypes[fieldType.Name.Value]; ok {
                return inputObjDef
            }
            panic(fmt.Sprintf("Unknown field type: %s", fieldType.Name.Value))
        }
    case *ast.List:
        // Handle list types recursively
        innerType := h.mapSchemaTypeToGraphQLType(fieldType.Type, customObjectTypes, customInputObjectTypes)
        return graphql.NewList(innerType)
    default:
        panic(fmt.Sprintf("Unsupported field type: %T", fieldType))
    }
}

// Creates argument configurations for GraphQL fields, mapping schema argument types to GraphQL types
func (h *GraphQLHandler) createArgumentsConfig(arguments []*ast.InputValueDefinition, customObjectTypes map[string]*graphql.Object, customInputObjectTypes map[string]*graphql.InputObject) graphql.FieldConfigArgument {
    args := graphql.FieldConfigArgument{}
    for _, arg := range arguments {
        argName := arg.Name.Value
        argType := arg.Type

        // Map argument schema type to GraphQL input type
        args[argName] = &graphql.ArgumentConfig{
            Type: h.mapSchemaTypeToGraphQLType(argType, customObjectTypes, customInputObjectTypes),
        }
    }
    return args
}

// Defines a custom scalar for JSON handling in GraphQL
var jsonScalar = graphql.NewScalar(graphql.ScalarConfig{
    Name: "JSON",
    Serialize: func(value interface{}) interface{} {
        return value
    },
    ParseValue: func(value interface{}) interface{} {
        return value
    },
    ParseLiteral: func(valueAST ast.Value) interface{} {
        switch value := valueAST.(type) {
        case *ast.ObjectValue:
            jsonValue := make(map[string]interface{})
            for _, field := range value.Fields {
                jsonValue[field.Name.Value] = parseValueFromAST(field.Value)
            }
            return jsonValue
        case *ast.ListValue:
            jsonArray := make([]interface{}, len(value.Values))
            for i, v := range value.Values {
                jsonArray[i] = parseValueFromAST(v)
            }
            return jsonArray
        default:
            return nil
        }
    },
})

// Recursively parses AST nodes into Go values
func parseValueFromAST(valueAST ast.Value) interface{} {
    switch value := valueAST.(type) {
    case *ast.StringValue:
        return value.Value
    case *ast.IntValue:
        return value.Value
    case *ast.FloatValue:
        return value.Value
    case *ast.BooleanValue:
        return value.Value
    case *ast.ObjectValue:
        objValue := make(map[string]interface{})
        for _, field := range value.Fields {
            objValue[field.Name.Value] = parseValueFromAST(field.Value)
        }
        return objValue
    case *ast.ListValue:
        arrayValue := make([]interface{}, len(value.Values))
        for i, v := range value.Values {
            arrayValue[i] = parseValueFromAST(v)
        }
        return arrayValue
    default:
        return nil
    }
}

// Handles executing GraphQL queries
func (h *GraphQLHandler) Handler() http.Handler {
    return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
        var params struct {
            Query         string                 `json:"query"`
            OperationName string                 `json:"operationName"`
            Variables     map[string]interface{} `json:"variables"`
        }

        // Parse the request body into a GraphQL query
        if err := json.NewDecoder(request.Body).Decode(&params); err != nil {
            http.Error(response, fmt.Sprintf(`{"error":"could not decode request body: %v"}`, err), http.StatusBadRequest)
            return
        }

        // Execute the GraphQL query against the schema
        result := graphql.Do(graphql.Params{
            Schema:         *h.schema,
            RequestString:  params.Query,
            OperationName:  params.OperationName,
            VariableValues: params.Variables,
            Context:        request.Context(),
        })

        // Return errors if any occurred during query execution
        if len(result.Errors) > 0 {
            response.WriteHeader(http.StatusBadRequest)
        }

        // Write the GraphQL result as JSON
        response.Header().Set("Content-Type", "application/json")
        if err := json.NewEncoder(response).Encode(result); err != nil {
            http.Error(response, fmt.Sprintf(`{"error":"could not encode response: %v"}`, err), http.StatusInternalServerError)
        }
    })
}

// Converts a camelCase string or map to an underscore_case representation recursively
func camelToUnderscoreRecursive(input interface{}) interface{} {
    switch v := input.(type) {
    case map[string]interface{}:
        result := make(map[string]interface{})
        for key, value := range v {
            newKey := camelToUnderscore(key)
            result[newKey] = camelToUnderscoreRecursive(value)
        }
        return result
    case []interface{}:
        for i, elem := range v {
            v[i] = camelToUnderscoreRecursive(elem)
        }
        return v
    default:
        return v
    }
}

// Converts a camelCase string to underscore_case
func camelToUnderscore(s string) string {
    var result []rune
    for i, r := range s {
        if i > 0 && r >= 'A' && r <= 'Z' {
            // Add underscore before an uppercase letter and convert to lowercase
            result = append(result, '_', r+('a'-'A'))
        } else if i > 0 && r >= '0' && r <= '9' {
            if !(s[i-1] >= 'a' && s[i-1] <= 'z') && !(s[i-1] >= '0' && s[i-1] <= '9') {
                // Add underscore before a number if the previous char is not a lowercase letter or number
                result = append(result, '_', r)
            } else {
                result = append(result, r)
            }
        } else {
            result = append(result, r)
        }
    }
    return string(result)
}

// Converts an underscore_case string or map to camelCase representation recursively
func underscoreToCamelCaseRecursive(input interface{}) interface{} {
    switch v := input.(type) {
    case map[string]interface{}:
        result := make(map[string]interface{})
        for key, value := range v {
            newKey := underscoreToCamelCase(key)
            result[newKey] = underscoreToCamelCaseRecursive(value)
        }
        return result
    case []interface{}:
        for i, elem := range v {
            v[i] = underscoreToCamelCaseRecursive(elem)
        }
        return v
    default:
        return v
    }
}

// Converts an underscore_case string to camelCase
func underscoreToCamelCase(s string) string {
    var result []rune
    upperNext := false

    for _, r := range s {
        if r == '_' {
            upperNext = true
        } else {
            if upperNext {
                result = append(result, r-('a'-'A'))
                upperNext = false
            } else {
                result = append(result, r)
            }
        }
    }
    return string(result)
}

