#ifndef LENET_IP_H
#define LENET_IP_H

#include <stdint.h>

#define LENET_BASE_ADDR   0xA0000000UL
#define LENET_MAP_SIZE    0x1000UL

#define LENET_START_OFF   0x00U
#define LENET_RESET_OFF   0x04U
#define LENET_WADDR_OFF   0x08U
#define LENET_WDATA_OFF   0x0CU
#define LENET_RESULT_OFF  0x10U
#define LENET_DONE_OFF    0x14U

#define LENET_IMG_SIZE    784U
#define LENET_NUM_IMAGES  1000U
#define LENET_TIMEOUT     100000000U

int  lenet_open(void);
void lenet_close(void);

void lenet_reset_core(void);
void lenet_write_pixel(uint16_t addr, int8_t pixel);
void lenet_load_image(const int8_t image[LENET_IMG_SIZE]);
void lenet_start(void);
int  lenet_wait_done(uint32_t timeout);
uint8_t lenet_get_result(void);

#endif