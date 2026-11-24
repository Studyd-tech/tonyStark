// MediaPipe C ABI declarations adapted from the Apache-2.0 licensed ctypes
// bindings shipped in mediapipe 1.2.3. Copyright 2022-2025 The MediaPipe Authors.
// See vendor/mediapipe/LICENSE and NOTICE. Keep this ABI pinned to that wheel;
// current upstream headers may have a different struct layout.
#include "CMediaPipe.h"
#include <dlfcn.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef struct {
    const char *buffer; unsigned int buffer_count; const char *path;
    int fd, delegate, host_environment, host_system;
    const char *host_version, *ca_bundle_path, *app_id, *app_version, *npu_dir;
} BaseOptions;
typedef struct {
    BaseOptions base;
    int mode, num_hands;
    float detection, presence, tracking;
    void (*callback)(void);
} HandOptions;
typedef struct {
    float x, y, z; bool has_visibility; float visibility;
    bool has_presence; float presence; const char *name;
} Landmark;
typedef struct { Landmark *landmarks; uint32_t count; } Landmarks;
typedef struct {
    void *handedness; uint32_t handedness_count;
    Landmarks *image; uint32_t image_count;
    Landmarks *world; uint32_t world_count;
} HandResult;

struct TSHandTracker {
    void *library, *task;
    int (*create)(HandOptions *, void **, char **);
    int (*image_create)(int, int, int, const uint8_t *, int, void **, char **);
    void (*image_free)(void *);
    int (*detect)(void *, void *, const void *, int64_t, HandResult *, char **);
    void (*result_free)(HandResult *);
    int (*close)(void *, char **);
    void (*error_free)(char *);
    uint8_t *rgba;
    size_t rgba_capacity;
};

static void message(char *out, size_t capacity, const char *text) {
    if (out && capacity) snprintf(out, capacity, "%s", text ? text : "Unknown hand tracker error");
}

void ts_hand_close(TSHandTracker *t) {
    if (!t) return;
    if (t->task && t->close) {
        char *error = NULL;
        t->close(t->task, &error);
        if (error && t->error_free) t->error_free(error);
    }
    free(t->rgba);
    // MediaPipe owns global thread pools. Retain the loaded image for process
    // lifetime; closing the last camera must not unload code used by those pools.
    free(t);
}

TSHandTracker *ts_hand_create(const char *library, const char *model, char *error, size_t capacity) {
    TSHandTracker *t = calloc(1, sizeof(*t));
    if (!t) { message(error, capacity, "Could not allocate hand tracker"); return NULL; }
    t->library = dlopen(library, RTLD_NOW | RTLD_LOCAL);
    if (!t->library) { message(error, capacity, dlerror()); ts_hand_close(t); return NULL; }
#define LOAD(field, symbol) do { *(void **)(&t->field) = dlsym(t->library, symbol); \
    if (!t->field) { message(error, capacity, "Missing MediaPipe symbol: " symbol); ts_hand_close(t); return NULL; } } while (0)
    LOAD(create, "MpHandLandmarkerCreate");
    LOAD(image_create, "MpImageCreateFromUint8Data");
    LOAD(image_free, "MpImageFree");
    LOAD(detect, "MpHandLandmarkerDetectForVideo");
    LOAD(result_free, "MpHandLandmarkerCloseResult");
    LOAD(close, "MpHandLandmarkerClose");
    LOAD(error_free, "MpErrorFree");
#undef LOAD
    HandOptions options = {0};
    options.base.path = model; options.base.fd = -1; options.base.delegate = 1; // CPU
    options.mode = 2; options.num_hands = TS_MAX_HANDS; // VIDEO, monotonic timestamps
    options.detection = 0.45f; options.presence = 0.45f; options.tracking = 0.45f;
    char *detail = NULL;
    int status = t->create(&options, &t->task, &detail);
    if (status != 0) message(error, capacity, detail);
    if (detail) t->error_free(detail);
    if (status != 0) { ts_hand_close(t); return NULL; }
    return t;
}

int ts_hand_detect(TSHandTracker *t, const uint8_t *bgra, int width, int height,
                   int stride, int64_t timestamp_ms, TSHandResult *out, char *error, size_t capacity) {
    if (out) memset(out, 0, sizeof(*out));
    if (!t || !out || !bgra || width <= 0 || height <= 0 || width > 4096 || height > 4096 || stride < width * 4) {
        message(error, capacity, "Invalid hand tracker frame"); return -1;
    }
    size_t count = (size_t)width * height * 4;
    if (t->rgba_capacity < count) {
        uint8_t *next = realloc(t->rgba, count);
        if (!next) { message(error, capacity, "Could not allocate camera frame"); return -1; }
        t->rgba = next; t->rgba_capacity = count;
    }
    // AVCapture provides padded BGRA rows; MediaPipe expects packed RGBA.
    for (int y = 0; y < height; y++) {
        const uint8_t *src = bgra + (size_t)y * stride;
        uint8_t *dst = t->rgba + (size_t)y * width * 4;
        for (int x = 0; x < width; x++) {
            dst[4*x] = src[4*x+2]; dst[4*x+1] = src[4*x+1];
            dst[4*x+2] = src[4*x]; dst[4*x+3] = 255;
        }
    }
    void *image = NULL;
    char *detail = NULL;
    int status = t->image_create(2, width, height, t->rgba, (int)count, &image, &detail);
    if (status != 0) {
        message(error, capacity, detail); if (detail) t->error_free(detail); return status;
    }
    if (detail) { t->error_free(detail); detail = NULL; }
    HandResult result = {0};
    status = t->detect(t->task, image, NULL, timestamp_ms, &result, &detail);
    if (status != 0) message(error, capacity, detail);
    if (detail) t->error_free(detail);
    if (status == 0) {
        if (result.image) {
            out->count = result.image_count < TS_MAX_HANDS ? result.image_count : TS_MAX_HANDS;
            for (unsigned int hand = 0; hand < out->count; hand++) {
                Landmarks points = result.image[hand];
                if (points.count == 21 && points.landmarks) {
                    out->hands[hand].has_image = 1;
                    for (int i = 0; i < 21; i++) {
                        Landmark p = points.landmarks[i];
                        out->hands[hand].image[i] = (TSJoint){p.x, p.y, p.z};
                    }
                }
                if (!result.world || hand >= result.world_count) continue;
                points = result.world[hand];
                if (points.count == 21 && points.landmarks) {
                    out->hands[hand].has_world = 1;
                    for (int i = 0; i < 21; i++) {
                        Landmark p = points.landmarks[i];
                        out->hands[hand].world[i] = (TSJoint){p.x, p.y, p.z};
                    }
                }
            }
        }
        t->result_free(&result);
    }
    t->image_free(image);
    return status;
}
