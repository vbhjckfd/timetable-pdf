PROJECT ?= timetable-252615
IMAGE   ?= gcr.io/$(PROJECT)/timetable-pdf
SERVICE ?= timetable-pdf
REGION  ?= europe-west1

.PHONY: build deploy

build:
	./build.sh

# Cloud Run resolves the tag to a digest at deploy time, so this always rolls
# out the image build just pushed. Env vars and other service settings are kept.
deploy: build
	gcloud run deploy $(SERVICE) \
		--project $(PROJECT) \
		--region $(REGION) \
		--image $(IMAGE) \
		--platform managed
