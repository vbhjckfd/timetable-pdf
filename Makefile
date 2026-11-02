PROJECT ?= timetable-252615
SERVICE ?= timetable-pdf
REGION  ?= europe-north1
IMAGE   ?= $(REGION)-docker.pkg.dev/$(PROJECT)/timetable/$(SERVICE):latest

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
	gcloud run services describe $(SERVICE) \
		--project $(PROJECT) --region $(REGION) \
		--format 'value(status.url,status.latestReadyRevisionName)'
