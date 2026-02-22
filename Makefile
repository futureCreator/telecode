.PHONY: all build clean test install cross-build help

# Variables
BINARY_NAME=telecode
MAIN_PACKAGE=./cmd/telecode
BUILD_DIR=./build
VERSION=$(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")
LDFLAGS=-ldflags "-X main.version=$(VERSION) -s -w -extldflags '-static'"
CGO_FLAGS=CGO_ENABLED=0

# Default target
all: build

# Build for current platform (statically linked)
build:
	@echo "🔨 Building $(BINARY_NAME) (statically linked)..."
	$(CGO_FLAGS) go build $(LDFLAGS) -o $(BINARY_NAME) $(MAIN_PACKAGE)
	@echo "✅ Build complete: $(BINARY_NAME)"
	@echo "📋 Binary info:"
	@file $(BINARY_NAME) || true
	@ls -lh $(BINARY_NAME)

# Build with race detector (for debugging) - cannot be static
build-race:
	@echo "🔨 Building with race detector (dynamically linked)..."
	go build -race $(LDFLAGS) -o $(BINARY_NAME)-race $(MAIN_PACKAGE)
	@echo "✅ Build complete: $(BINARY_NAME)-race"

# Cross-platform builds (all statically linked)
cross-build: build-linux build-darwin build-windows
	@echo "✅ All cross-platform builds complete"

build-linux:
	@echo "🐧 Building for Linux (statically linked)..."
	@mkdir -p $(BUILD_DIR)
	$(CGO_FLAGS) GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-amd64 $(MAIN_PACKAGE)
	$(CGO_FLAGS) GOOS=linux GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-linux-arm64 $(MAIN_PACKAGE)
	@echo "✅ Linux builds complete"

build-darwin:
	@echo "🍎 Building for macOS (statically linked)..."
	@mkdir -p $(BUILD_DIR)
	$(CGO_FLAGS) GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-amd64 $(MAIN_PACKAGE)
	$(CGO_FLAGS) GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-darwin-arm64 $(MAIN_PACKAGE)
	@echo "✅ macOS builds complete"

build-windows:
	@echo "🪟 Building for Windows (statically linked)..."
	@mkdir -p $(BUILD_DIR)
	$(CGO_FLAGS) GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o $(BUILD_DIR)/$(BINARY_NAME)-windows-amd64.exe $(MAIN_PACKAGE)
	@echo "✅ Windows build complete"

# Install locally
install: build
	@echo "📦 Installing $(BINARY_NAME)..."
	$(CGO_FLAGS) go install $(LDFLAGS) $(MAIN_PACKAGE)
	@echo "✅ Installed to $(GOPATH)/bin or $(HOME)/go/bin"

# Install to /usr/local/bin (requires sudo)
install-system: build
	@echo "📦 Installing $(BINARY_NAME) to /usr/local/bin..."
	@sudo cp $(BINARY_NAME) /usr/local/bin/
	@sudo chmod +x /usr/local/bin/$(BINARY_NAME)
	@echo "✅ Installed to /usr/local/bin/$(BINARY_NAME)"

# Run tests
test:
	@echo "🧪 Running tests..."
	go test -v ./...
	@echo "✅ Tests complete"

# Run tests with coverage
test-coverage:
	@echo "🧪 Running tests with coverage..."
	go test -coverprofile=coverage.out ./...
	go tool cover -html=coverage.out -o coverage.html
	@echo "✅ Coverage report generated: coverage.html"

# Format code
fmt:
	@echo "📝 Formatting code..."
	go fmt ./...
	@echo "✅ Formatting complete"

# Run linter (requires golangci-lint)
lint:
	@echo "🔍 Running linter..."
	@if command -v golangci-lint >/dev/null 2>&1; then \
		golangci-lint run; \
	else \
		echo "⚠️  golangci-lint not installed. Install with:"; \
		echo "    go install github.com/golangci/golangci-lint/cmd/golangci-lint@latest"; \
	fi

# Tidy go modules
tidy:
	@echo "🧹 Tidying go modules..."
	go mod tidy
	@echo "✅ Modules tidied"

# Download dependencies
deps:
	@echo "📥 Downloading dependencies..."
	go mod download
	@echo "✅ Dependencies downloaded"

# Update dependencies
update-deps:
	@echo "⬆️  Updating dependencies..."
	go get -u ./...
	go mod tidy
	@echo "✅ Dependencies updated"

# Generate example config
generate-config:
	@echo "⚙️  Generating example configuration..."
	@mkdir -p ~/.telecode
	$(CGO_FLAGS) go run $(LDFLAGS) $(MAIN_PACKAGE) -generate-config
	@echo "✅ Example config generated: telecode.yml"

# Clean build artifacts
clean:
	@echo "🧹 Cleaning build artifacts..."
	@rm -f $(BINARY_NAME)
	@rm -f $(BINARY_NAME)-race
	@rm -rf $(BUILD_DIR)
	@rm -f coverage.out coverage.html
	@echo "✅ Clean complete"

# Run the application (requires config)
run: build
	@echo "🚀 Running $(BINARY_NAME)..."
	./$(BINARY_NAME)

# Run with specific config
run-config: build
	@echo "🚀 Running $(BINARY_NAME) with telecode.yml..."
	./$(BINARY_NAME) -config telecode.yml

# Development mode with hot reload (requires air)
dev:
	@if command -v air >/dev/null 2>&1; then \
		air; \
	else \
		echo "⚠️  air not installed. Install with:"; \
		echo "    go install github.com/cosmtrek/air@latest"; \
		exit 1; \
	fi

# Verify static linking
verify-static:
	@echo "🔍 Verifying static linking..."
	@if command -v ldd >/dev/null 2>&1; then \
		if ldd $(BINARY_NAME) 2>&1 | grep -q "not a dynamic executable"; then \
			echo "✅ Binary is statically linked"; \
		else \
			echo "⚠️  Binary may have dynamic dependencies:"; \
			ldd $(BINARY_NAME) || true; \
		fi \
	elif command -v otool >/dev/null 2>&1; then \
		echo "📋 Checking dynamic libraries on macOS:"; \
		otool -L $(BINARY_NAME) | head -5; \
	else \
		echo "⚠️  Cannot verify static linking (no ldd or otool available)"; \
	fi

# Show help
help:
	@echo "Telecode Makefile"
	@echo ""
	@echo "Usage:"
	@echo "  make [target]"
	@echo ""
	@echo "Targets:"
	@echo "  all              - Build the binary (default, static)"
	@echo "  build            - Build for current platform (statically linked)"
	@echo "  build-race       - Build with race detector (dynamic, for debugging)"
	@echo "  cross-build      - Build for all platforms (Linux, macOS, Windows, all static)"
	@echo "  install          - Install to GOPATH/bin (static)"
	@echo "  install-system   - Install to /usr/local/bin (requires sudo)"
	@echo "  test             - Run tests"
	@echo "  test-coverage    - Run tests with coverage report"
	@echo "  fmt              - Format code with go fmt"
	@echo "  lint             - Run golangci-lint"
	@echo "  tidy             - Tidy go modules"
	@echo "  deps             - Download dependencies"
	@echo "  update-deps      - Update all dependencies"
	@echo "  generate-config  - Generate example configuration file"
	@echo "  clean            - Remove build artifacts"
	@echo "  run              - Build and run the application"
	@echo "  run-config       - Run with telecode.yml config"
	@echo "  dev              - Run with hot reload (requires air)"
	@echo "  verify-static    - Verify binary is statically linked"
	@echo "  help             - Show this help message"
	@echo ""
	@echo "Examples:"
	@echo "  make build                    # Build for current platform (static)"
	@echo "  make cross-build              # Build for all platforms"
	@echo "  make install-system           # Install system-wide"
	@echo "  make test                     # Run tests"
	@echo "  make verify-static            # Check static linking"
