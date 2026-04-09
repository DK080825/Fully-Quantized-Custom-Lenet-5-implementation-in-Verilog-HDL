#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

#include "lenet_ip.h"

#define IMAGE_FILE_PATH        "mnist_uint8_1000.txt"
#define LABEL_FILE_PATH        "mnist_label_1000.txt"
#define IMAGE_LINE_BUF_SZ      8192

static uint8_t g_images[LENET_NUM_IMAGES][LENET_IMG_SIZE];
static uint8_t g_labels[LENET_NUM_IMAGES];

/*==============================================================================
 * Time utility: return time in microseconds
 *============================================================================*/
static uint64_t get_time_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ((uint64_t)ts.tv_sec * 1000000ULL) + ((uint64_t)ts.tv_nsec / 1000ULL);
}

/*==============================================================================
 * Parse one image line: exactly LENET_IMG_SIZE unsigned values in range [0..255]
 *============================================================================*/
static int parse_image_line(char *line, uint8_t image[LENET_IMG_SIZE])
{
    uint32_t count = 0U;
    char *tok = strtok(line, " ,\t\r\n");

    while (tok != NULL) {
        char *endptr = NULL;
        long v = strtol(tok, &endptr, 10);

        if (endptr == tok || *endptr != '\0') {
            return -1;
        }
        if (v < 0 || v > 255) {
            return -2;
        }
        if (count >= LENET_IMG_SIZE) {
            return -3;
        }

        image[count++] = (uint8_t)v;
        tok = strtok(NULL, " ,\t\r\n");
    }

    if (count != LENET_IMG_SIZE) {
        return -4;
    }

    return 0;
}

/*==============================================================================
 * Load images
 *============================================================================*/
static int load_images_from_file(const char *path,
                                 uint8_t images[LENET_NUM_IMAGES][LENET_IMG_SIZE])
{
    FILE *fp;
    char line[IMAGE_LINE_BUF_SZ];
    uint32_t idx = 0U;

    fp = fopen(path, "r");
    if (fp == NULL) {
        perror("fopen image file");
        return -1;
    }

    while (idx < LENET_NUM_IMAGES) {
        if (fgets(line, sizeof(line), fp) == NULL) {
            break;
        }

        if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0') {
            continue;
        }

        if (parse_image_line(line, images[idx]) != 0) {
            printf("[ERROR] Invalid image format at image %lu\n",
                   (unsigned long)idx);
            fclose(fp);
            return -2;
        }

        idx++;
    }

    fclose(fp);

    if (idx != LENET_NUM_IMAGES) {
        printf("[ERROR] Expected %u images but found %lu\n",
               LENET_NUM_IMAGES,
               (unsigned long)idx);
        return -3;
    }

    return 0;
}

/*==============================================================================
 * Load labels
 *============================================================================*/
static int load_labels_from_file(const char *path, uint8_t labels[LENET_NUM_IMAGES])
{
    FILE *fp;
    char line[64];
    uint32_t idx = 0U;

    fp = fopen(path, "r");
    if (fp == NULL) {
        perror("fopen label file");
        return -1;
    }

    while (idx < LENET_NUM_IMAGES) {
        char *endptr = NULL;
        long v;

        if (fgets(line, sizeof(line), fp) == NULL) {
            break;
        }

        if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0') {
            continue;
        }

        v = strtol(line, &endptr, 10);

        if (endptr == line ||
            (*endptr != '\n' && *endptr != '\r' && *endptr != '\0')) {
            printf("[ERROR] Invalid label format at line %lu\n",
                   (unsigned long)(idx + 1U));
            fclose(fp);
            return -2;
        }

        if (v < 0 || v > 9) {
            printf("[ERROR] Invalid label value at line %lu\n",
                   (unsigned long)(idx + 1U));
            fclose(fp);
            return -3;
        }

        labels[idx++] = (uint8_t)v;
    }

    fclose(fp);

    if (idx != LENET_NUM_IMAGES) {
        printf("[ERROR] Expected %u labels but found %lu\n",
               LENET_NUM_IMAGES,
               (unsigned long)idx);
        return -4;
    }

    return 0;
}

/*==============================================================================
 * Main
 *============================================================================*/
int main(void)
{
    uint32_t i;
    uint32_t correct = 0U;
    uint32_t fail = 0U;

    uint64_t total_infer_us = 0ULL;
    uint64_t min_infer_us = UINT64_MAX;
    uint64_t max_infer_us = 0ULL;
    uint32_t timed_runs = 0U;

    printf("============================================================\n");
    printf("LeNet INT8 Inference Test\n");
    printf("============================================================\n");

    if (load_images_from_file(IMAGE_FILE_PATH, g_images) != 0) {
        printf("[ERROR] Failed to load images from %s\n", IMAGE_FILE_PATH);
        return -1;
    }

    if (load_labels_from_file(LABEL_FILE_PATH, g_labels) != 0) {
        printf("[ERROR] Failed to load labels from %s\n", LABEL_FILE_PATH);
        return -2;
    }

    if (lenet_open() != 0) {
        printf("[ERROR] Failed to open LeNet IP\n");
        return -3;
    }

    for (i = 0U; i < LENET_NUM_IMAGES; i++) {
        uint8_t pred;
        uint64_t t_start_us;
        uint64_t t_done_us;
        uint64_t infer_us;

        lenet_reset_core();
        lenet_load_image(g_images[i]);

        t_start_us = get_time_us();
        lenet_start();

        if (lenet_wait_done(LENET_TIMEOUT) != 0) {
            printf("[FAIL] img=%4lu pred=NA label=%u time=TIMEOUT\n",
                   (unsigned long)i,
                   g_labels[i]);
            fail++;
            continue;
        }

        t_done_us = get_time_us();
        infer_us = t_done_us - t_start_us;

        pred = lenet_get_result();

        total_infer_us += infer_us;
        timed_runs++;

        if (infer_us < min_infer_us) {
            min_infer_us = infer_us;
        }
        if (infer_us > max_infer_us) {
            max_infer_us = infer_us;
        }

        if (pred == g_labels[i]) {
            correct++;
            printf("[PASS] img=%4lu pred=%u label=%u time=%lu us\n",
                   (unsigned long)i,
                   pred,
                   g_labels[i],
                   (unsigned long)infer_us);
        } else {
            fail++;
            printf("[FAIL] img=%4lu pred=%u label=%u time=%lu us\n",
                   (unsigned long)i,
                   pred,
                   g_labels[i],
                   (unsigned long)infer_us);
        }
    }

    printf("============================================================\n");
    printf("Test Summary\n");
    printf("============================================================\n");
    printf("Total images          : %u\n", LENET_NUM_IMAGES);
    printf("Passed                : %u\n", correct);
    printf("Failed                : %u\n", fail);

    if (LENET_NUM_IMAGES > 0U) {
        double accuracy = (100.0 * (double)correct) / (double)LENET_NUM_IMAGES;
        printf("Accuracy              : %.2f%% (%u/%u)\n",
               accuracy,
               correct,
               LENET_NUM_IMAGES);
    } else {
        printf("Accuracy              : N/A\n");
    }

    if (timed_runs > 0U) {
        double avg_infer_us = (double)total_infer_us / (double)timed_runs;
        printf("Single-image latency  :\n");
        printf("  Average             : %.2f us\n", avg_infer_us);
        printf("  Minimum             : %lu us\n", (unsigned long)min_infer_us);
        printf("  Maximum             : %lu us\n", (unsigned long)max_infer_us);
    } else {
        printf("Single-image latency  : N/A\n");
    }

    lenet_close();
    printf("============================================================\n");
    printf("Inference completed\n");
    printf("============================================================\n");

    return 0;
}