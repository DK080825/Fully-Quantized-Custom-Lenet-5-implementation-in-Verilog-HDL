#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

#include "lenet_ip.h"

#define IMAGE_FILE_PATH   "mnist_int8_1000.txt"
#define LABEL_FILE_PATH   "mnist_label_1000.txt"
#define IMAGE_LINE_BUF_SZ 8192

static int8_t  g_images[LENET_NUM_IMAGES][LENET_IMG_SIZE];
static uint8_t g_labels[LENET_NUM_IMAGES];

static int parse_image_line(char *line, int8_t image[LENET_IMG_SIZE])
{
    uint32_t count = 0U;
    char *tok = strtok(line, " ,\t\r\n");

    while (tok != NULL) {
        char *endptr;
        long v = strtol(tok, &endptr, 10);

        if (*endptr != '\0') {
            return -1;
        }
        if (v < -128 || v > 127) {
            return -2;
        }
        if (count >= LENET_IMG_SIZE) {
            return -3;
        }

        image[count++] = (int8_t)v;
        tok = strtok(NULL, " ,\t\r\n");
    }

    if (count != LENET_IMG_SIZE) {
        return -4;
    }

    return 0;
}

static int load_images_from_file(const char *path,
                                 int8_t images[LENET_NUM_IMAGES][LENET_IMG_SIZE])
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
            printf("ERROR: bad image format at image %lu\n", (unsigned long)idx);
            fclose(fp);
            return -2;
        }

        idx++;
    }

    fclose(fp);

    if (idx != LENET_NUM_IMAGES) {
        printf("ERROR: expected %u images but found %lu\n",
               LENET_NUM_IMAGES, (unsigned long)idx);
        return -3;
    }

    return 0;
}

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
        char *endptr;
        long v;

        if (fgets(line, sizeof(line), fp) == NULL) {
            break;
        }

        if (line[0] == '\n' || line[0] == '\r' || line[0] == '\0') {
            continue;
        }

        v = strtol(line, &endptr, 10);
        if (v < 0 || v > 9) {
            printf("ERROR: invalid label at line %lu\n", (unsigned long)(idx + 1U));
            fclose(fp);
            return -2;
        }

        labels[idx++] = (uint8_t)v;
    }

    fclose(fp);

    if (idx != LENET_NUM_IMAGES) {
        printf("WARNING: expected %u labels but found %lu\n",
               LENET_NUM_IMAGES, (unsigned long)idx);
        return -3;
    }

    return 0;
}

int main(void)
{
    uint32_t i;
    uint32_t correct = 0U;
    int labels_valid = 0;

    printf("LeNet inference start\n");

    if (load_images_from_file(IMAGE_FILE_PATH, g_images) != 0) {
        printf("ERROR: failed to load images\n");
        return -1;
    }

    if (load_labels_from_file(LABEL_FILE_PATH, g_labels) == 0) {
        labels_valid = 1;
    } else {
        printf("Proceeding without label comparison\n");
    }

    if (lenet_open() != 0) {
        printf("ERROR: failed to map LeNet IP\n");
        return -2;
    }

    for (i = 0U; i < LENET_NUM_IMAGES; i++) {
        uint8_t pred;

        lenet_reset_core();
        lenet_load_image(g_images[i]);
        lenet_start();

        if (lenet_wait_done(LENET_TIMEOUT) != 0) {
            printf("ERROR: timeout on image %lu\n", (unsigned long)i);
            continue;
        }

        pred = lenet_get_result();

        if (labels_valid) {
            printf("img=%lu pred=%u label=%u %s\n",
                   (unsigned long)i,
                   pred,
                   g_labels[i],
                   (pred == g_labels[i]) ? "OK" : "FAIL");

            if (pred == g_labels[i]) {
                correct++;
            }
        } else {
            printf("img=%lu pred=%u\n",
                   (unsigned long)i,
                   pred);
        }
    }

    if (labels_valid) {
        printf("Accuracy = %lu / %u\n",
               (unsigned long)correct,
               LENET_NUM_IMAGES);
    }

    lenet_close();

    printf("LeNet inference done\n");
    return 0;
}