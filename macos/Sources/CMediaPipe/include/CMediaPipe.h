#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct TSHandTracker TSHandTracker;
typedef struct { float x, y, z; } TSJoint;
#define TS_MAX_HANDS 2
typedef struct {
    int has_image;
    int has_world;
    TSJoint image[21];
    TSJoint world[21];
} TSHand;
typedef struct {
    unsigned int count;
    TSHand hands[TS_MAX_HANDS];
} TSHandResult;

TSHandTracker *ts_hand_create(const char *library, const char *model, char *error, size_t capacity);
int ts_hand_detect(TSHandTracker *tracker, const uint8_t *bgra, int width, int height,
                   int stride, int64_t timestamp_ms, TSHandResult *result, char *error, size_t capacity);
void ts_hand_close(TSHandTracker *tracker);
