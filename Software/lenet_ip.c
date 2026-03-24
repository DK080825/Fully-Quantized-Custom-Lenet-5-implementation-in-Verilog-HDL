#include "lenet_ip.h"

#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/mman.h>

static int g_mem_fd = -1;
static volatile uint32_t *g_lenet_base = NULL;

static inline void reg_write(uint32_t offset, uint32_t value)
{
    g_lenet_base[offset >> 2] = value;
}

static inline uint32_t reg_read(uint32_t offset)
{
    return g_lenet_base[offset >> 2];
}

int lenet_open(void)
{
    g_mem_fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (g_mem_fd < 0) {
        perror("open(/dev/mem)");
        return -1;
    }

    g_lenet_base = (volatile uint32_t *)mmap(
        NULL,
        LENET_MAP_SIZE,
        PROT_READ | PROT_WRITE,
        MAP_SHARED,
        g_mem_fd,
        LENET_BASE_ADDR
    );

    if (g_lenet_base == MAP_FAILED) {
        perror("mmap");
        g_lenet_base = NULL;
        close(g_mem_fd);
        g_mem_fd = -1;
        return -1;
    }

    return 0;
}

void lenet_close(void)
{
    if (g_lenet_base != NULL) {
        munmap((void *)g_lenet_base, LENET_MAP_SIZE);
        g_lenet_base = NULL;
    }

    if (g_mem_fd >= 0) {
        close(g_mem_fd);
        g_mem_fd = -1;
    }
}

void lenet_reset_core(void)
{
    reg_write(LENET_RESET_OFF, 1U);
}

void lenet_write_pixel(uint16_t addr, int8_t pixel)
{
    reg_write(LENET_WADDR_OFF, (uint32_t)addr);
    reg_write(LENET_WDATA_OFF, (uint32_t)(uint8_t)pixel);
}

void lenet_load_image(const int8_t image[LENET_IMG_SIZE])
{
    uint16_t i;
    for (i = 0; i < LENET_IMG_SIZE; i++) {
        lenet_write_pixel(i, image[i]);
    }
}

void lenet_start(void)
{
    reg_write(LENET_START_OFF, 1U);
}

int lenet_wait_done(uint32_t timeout)
{
    uint32_t i;
    for (i = 0; i < timeout; i++) {
        if (reg_read(LENET_DONE_OFF) & 0x1U) {
            return 0;
        }
    }
    return -1;
}

uint8_t lenet_get_result(void)
{
    return (uint8_t)(reg_read(LENET_RESULT_OFF) & 0x0FU);
}