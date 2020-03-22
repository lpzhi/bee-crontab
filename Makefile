#
# Tweak the variables based on your project.
#

# This repo's root import path (under GOPATH).
ROOT := github.com/sinksmell/bee-crontab

# Target binaries. You can build multiple binaries for a single project.
TARGETS := master worker

# Container image prefix and suffix added to targets.
# The final built images are:
#   $[REGISTRY]/$[IMAGE_PREFIX]$[TARGET]$[IMAGE_SUFFIX]:$[VERSION]
# $[REGISTRY] is an item from $[REGISTRIES], $[TARGET] is an item from $[TARGETS].
IMAGE_PREFIX ?= $(strip bee-crontab-)
IMAGE_SUFFIX ?= $(strip )

# Container registries.
# set your dockerhub username or docker registry url
REGISTRY ?= destory

# Container registry for base images.
BASE_REGISTRY ?= 0c7swsv7.mirror.aliyuncs.com/library

#
# These variables should not need tweaking.
#

# It's necessary to set this because some environments don't link sh -> bash.
SHELL := /bin/bash

# Project main package location (can be multiple ones).
CMD_DIR := ./cmd

# Project output directory.
OUTPUT_DIR := ./bin

# Build direcotory.
BUILD_DIR := ./build

# Current version of the project.
VERSION ?= $(shell git describe --tags --always --dirty)

# Available cpus for compiling, please refer to https://github.com/caicloud/engineering/issues/8186#issuecomment-518656946 for more information.
CPUS ?= $(shell sh hack/read_cpus_available.sh)

# Track code version with Docker Label.
DOCKER_LABELS ?= git-describe="$(shell date -u +v%Y%m%d)-$(shell git describe --tags --always --dirty)"

# Golang standard bin directory.
GOPATH ?= $(shell go env GOPATH)
BIN_DIR := $(GOPATH)/bin
GOLANGCI_LINT := $(BIN_DIR)/golangci-lint

#
# Define all targets. At least the following commands are required:
#

# All targets.
.PHONY: lint test build container push

build: build-local

# more info about `GOGC` env: https://github.com/golangci/golangci-lint#memory-usage-of-golangci-lint
lint: $(GOLANGCI_LINT)
	@GOGC=5 $(GOLANGCI_LINT) run

$(GOLANGCI_LINT):
	curl -sfL https://install.goreleaser.com/github.com/golangci/golangci-lint.sh | sh -s -- -b $(BIN_DIR) v1.16.0

test:
	@go test -p $(CPUS) $$(go list ./... | grep -v /vendor | grep -v /test) -coverprofile=coverage.out
	@go tool cover -func coverage.out | tail -n 1 | awk '{ print "Total coverage: " $$3 }'

build-local:
	@for target in $(TARGETS); do                                                      \
	  go build -i -v -o $(OUTPUT_DIR)/$${target} -p $(CPUS)                            \
	  -ldflags "-s -w -X $(ROOT)/version.VERSION=$(VERSION)"																	\
	  $(CMD_DIR)/$${target};                                                           \
	done

build-linux:
	@docker run --rm                                                                   \
	  -v $(PWD):/go/src/$(ROOT)                                                        \
	  -w /go/src/$(ROOT)                                                               \
	  -e GOOS=linux                                                                    \
	  -e GOARCH=amd64                                                                  \
	  -e GO111MODULE=on                                                                    \
	  -e GOPROXY=https://goproxy.cn,direct                                                                    \
	  $(BASE_REGISTRY)/golang:1.13-stretch                                           \
	    /bin/bash -c 'for target in $(TARGETS); do                                     \
	      go build -i -v -o $(OUTPUT_DIR)/$${target} -p $(CPUS)                        \
	        -ldflags "-s -w -X $(ROOT)/version.VERSION=$(VERSION)"                                 \
	        $(CMD_DIR)/$${target};                                                     \
	    done'

container: build-linux
	@for target in $(TARGETS); do                                                      \
	  image=$(IMAGE_PREFIX)$${target}$(IMAGE_SUFFIX);                                  \
	  docker build -t $(REGISTRY)/$${image}:$(VERSION)                                 \
	    --label $(DOCKER_LABELS)                                                       \
	    -f $(BUILD_DIR)/$${target}/Dockerfile .;                                       \
	done

push: container
	@for target in $(TARGETS); do                                                      \
	  image=$(IMAGE_PREFIX)$${target}$(IMAGE_SUFFIX);                                  \
	  docker push $(REGISTRY)/$${image}:$(VERSION);                                    \
	done

.PHONY: clean
clean:
	@-rm -vrf ${OUTPUT_DIR}