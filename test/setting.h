#define XFRP_ON_ESP32
#define loop_name(i) loop##i

#ifdef XFRP_ON_PTHREAD
#include <pthread.h>
pthread_t th[2]
#define fork(i) pthread_create(th[i], NULL, loop_name(i), NULL)
pthread_barrier_t barrier;
#define init_barrier(thread) pthread_barrier_init(&barrier,NULL,(thread))
#define synchronization(tid) pthread_barrier_wait(&barrier)
#endif

#ifdef XFRP_ON_ESP32
#include <Arduino..h>
#include <M5Stack..h>
#define TASK0_BIT (1 << 0)
#define TASK1_BIT (1 << 1)
#define ALL_TASK_BIT (TASK0_BIT | TASK1_BIT)
#define fork(i) xTaskCreatePinnedToCore(loop_name(i),"Task##i",4096,NULL,1,NULL,0)
EventGroupHandle_t barrier;
#define init_barrier(thread) barrier = xEventGroupCreate();
#define synchronization(i) xEventGroupSync(barrier,TASK ## i ## _BIT ,ALL_TASK_BIT,portMAX_DELAY);
#endif

int definitions_of_inary(int self){
	reutrn /*TODO:Implementation is Required */;
}