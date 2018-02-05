/* 
 ---------------------------------------------
     echemsub.c          2018/01/18
     Copyright (c) 2018 Toshi Nagata,
   released under the MIT open source license.
 ---------------------------------------------
*/

#include <unistd.h>
#include <pthread.h>
#include <time.h>
#include <sys/time.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <linux/spi/spidev.h>
#include <fcntl.h>
#include <sys/ioctl.h>
#include <wiringPi.h>
#include <sched.h>

#if 0
#pragma mark ====== SPI ======
#endif

struct spi_info {
	int fd;
	int speed;
	int mode;
	int bpw;
};

static struct spi_info s_spi_infos[6] = {{-1}, {-1}, {-1}, {-1}, {-1}, {-1}};

int gpio_pin, spi_ch1, spi_ch2;

int
spi_checkchannel(int ch)
{
	switch (ch) {
		case 0: case 1: case 2: break;
		case 10: case 11: case 12: ch -= 7; break;
		default:
			return -1;
	}
	return ch;
}
	
/*  spi.setup(channel, speed, mode=0, bpw=8))  */
int
spi_setup(int ch, int speed, int mode, int bpw)
{
	int n;
	char dname[16];
	if (bpw == 0)
		bpw = 8;
	ch = spi_checkchannel(ch);
	if (ch < 0)
		return -1;  /*  Bad channel number  */
	if ((n = s_spi_infos[ch].fd) < 0) {
		snprintf(dname, sizeof(dname), "/dev/spidev%d.%d", ch / 3, ch % 3);
		n = open(dname, O_RDWR);
		if (n < 0)
			return -2;  /*  Cannot open SPI device  */
		s_spi_infos[ch].fd = n;
	}
	if (ioctl(n, SPI_IOC_WR_MODE, &mode) < 0) {
		close(n);
		return -3;  /*  Cannot set SPI write mode  */
	}
	if (ioctl(n, SPI_IOC_WR_BITS_PER_WORD, &bpw) < 0) {
		close(n);
		return -4;  /*  Cannot set SPI write bits-per-word  */
	}
	if (ioctl(n, SPI_IOC_WR_MAX_SPEED_HZ, &speed) < 0) {
		close(n);
		return -5;  /*  Cannot set SPI write speed  */
	}
	if (ioctl(n, SPI_IOC_RD_MODE, &mode) < 0) {
		close(n);
		return -6;  /*  Cannot set SPI read mode  */
	}
	if (ioctl(n, SPI_IOC_RD_BITS_PER_WORD, &bpw) < 0) {
		close(n);
		return -7;  /*  Cannot set SPI read bits-per-word  */
	}
	if (ioctl(n, SPI_IOC_RD_MAX_SPEED_HZ, &speed) < 0) {
		close(n);
		return -8;  /*  Cannot set SPI read speed  */
	}
	s_spi_infos[ch].speed = speed;
	s_spi_infos[ch].mode = mode;
	s_spi_infos[ch].bpw = bpw;
	return 0;
}

/*  Internal routine for SPI read/write; flag = 1: read, 2: write, 3: both  */
/*  up[0..length-1]: out buffer, up[length..length*2-1]: in buffer  */
static int
spi_readwrite_sub(int ch, unsigned char *p, int length, int flag)
{
	int i, len;
	struct spi_ioc_transfer tr;
	ch = spi_checkchannel(ch);
	if (ch < 0)
		return -1;
	memset(&tr, 0, sizeof(tr));
	tr.tx_buf = (unsigned long)p;
	tr.rx_buf = (unsigned long)(p + length);
	tr.len = length;
	tr.delay_usecs = 0;
	tr.speed_hz = s_spi_infos[ch].speed;
	tr.bits_per_word = s_spi_infos[ch].bpw;
	tr.cs_change = 0;
	if (ioctl(s_spi_infos[ch].fd, SPI_IOC_MESSAGE(1), &tr) < 0)
		return -2;
	return 0;
}

int
spi_read(int ch, unsigned char *p, int length)
{
	return spi_readwrite_sub(ch, p, length, 1);
}

int
spi_write(int ch, unsigned char *p, int length)
{
	return spi_readwrite_sub(ch, p, length, 2);
}

int
spi_readwrite(int ch, unsigned char *p, int length)
{
	return spi_readwrite_sub(ch, p, length, 3);
}

int
spi_close(int ch)
{
	ch = spi_checkchannel(ch);
	if (ch < 0)
		return -1;  /*  Bad SPI number  */
	if (s_spi_infos[ch].fd < 0)
		return 0;
	close(s_spi_infos[ch].fd);
	return 0;
}

#if 0
#pragma mark ====== GPIO ======
#endif

int
gpio_setup(void)
{
	static int setup_called = 0;
	if (setup_called)
		return 0;
	setup_called = 1;
	if (getenv("WIRINGPI_GPIOMEM") == NULL)
		setenv("WIRINGPI_GPIOMEM", "1", 1);
	wiringPiSetup();
	return 0;
}

#if 0
#pragma mark ====== AD/DA conversion thread ======
#endif

/*  Usage:
 *  int conv_init(int ch1, int speed1, int ch2, int speed2, int gpio);
 *    Open the SPI channel ch1 for DA (output), ch2 for AD (input).
 *    The thread is created and made ready-to-run.
 *  int conv_quit(void);
 *    Quit the conversion thread.
 *  int conv_reset(void);
 *    Reset the conversion thread. All pending I/O are discarded, and the timer is set to zero.
 *  int conv_queue(double stamp, int outdata);
 *    Put a data with timestamp in the queue. Returns non-zero if the queue is full.
 *  int conv_start(void);
 *    Start conversion. The output data is sent if the
 *    present timer exceeds the timestamp. The input data is acquired and set in the queue.
 *    The timestamp is updated to the actual value at the SPI transfer.
 *  int conv_read(double *stamp, int *outdata, int *indata);
 *    Get the next input data. Returns non-zero if no data is available.
 *  int conv_stop(void);
 *    Stop conversion loop. It can be restarted by conv_start().
 */

#define CONV_BUFSIZE 32768
struct conv_record {
	double stamp;
	int outdata;
	int indata;
};
int conv_ch1, conv_ch2;
struct conv_record conv_buf[CONV_BUFSIZE];
int conv_write_idx = 0;
int conv_send_idx = 0;
int conv_read_idx = 0;
int conv_state = 0;  /*  0: pending, 1: running, 2: quit  */
double start_time = 0.0;
double current_time = 0.0;
struct timespec start_timespec;
int last_output = -1;
int last_input = -1;
pthread_t th;
pthread_mutex_t mutex;

/*  Write data to MCP4922  */
static int
conv_direct_write_nolock(int val)
{
	unsigned char a[4];
	a[0] = 0x30 + ((val >> 8) & 0x0f);
	a[1] = (val & 0xff);
	digitalWrite(gpio_pin, 1);
	spi_readwrite(spi_ch1, a, 2);
	digitalWrite(gpio_pin, 0);
	last_output = val;
	return 0;
}

/*  Read data from MCP3204  */
static int
conv_direct_read_nolock(void)
{
	int val, i;
	int vals[8];
	unsigned char a[6];
	val = 0;
	for (i = 0; i < 7; i++) {
		a[0] = 0x06;  /*  Single channel  */
		a[1] = 0x00;  /*  CH0  */
		a[2] = 0;
		spi_readwrite(spi_ch2, a, 3);
		vals[i] = (a[4] & 0x0f) * 256 + (a[5] & 0xff);
	}
	/*  Sort values  */
	for (i = 1; i < 7; i++) {
		val = vals[i];
		if (vals[i - 1] > val) {
			int j = i;
			do {
				vals[j] = vals[j - 1];
				j--;
			} while (j > 0 && vals[j - 1] > val);
			vals[j] = val;
		}
	}
	/*  Median  */
	val = vals[3];
	/*  Olympic; it looks like median is better  */
/*	val = (vals[1] + vals[2] + vals[3] + vals[4] + vals[5]) / 5;  */
	last_input = val;
	return val;
}

int
conv_direct_write(int val)
{
	pthread_mutex_lock(&mutex);
	conv_direct_write_nolock(val);
	pthread_mutex_unlock(&mutex);
}

int
conv_direct_read(void)
{
	int retval;
	pthread_mutex_lock(&mutex);
	retval = conv_direct_read_nolock();
	pthread_mutex_unlock(&mutex);
	return retval;
}

int
conv_last_output(void)
{
	return last_output;
}

int
conv_last_input(void)
{
	return last_input;
}

void *
thread_entry(void *ptr)
{
	double wait_timestamp;
	struct timespec spec;
	clock_gettime(CLOCK_REALTIME, &start_timespec);
	while (1) {
		int state = conv_state;
		if (conv_state == 2)
			break;
		if (conv_state == 0) {
			spec.tv_sec = 0;
			spec.tv_nsec = 2000000;
			clock_nanosleep(CLOCK_REALTIME, 0, &spec, NULL);
			continue;
		}
		clock_gettime(CLOCK_REALTIME, &spec);
		current_time = (spec.tv_sec - start_timespec.tv_sec) + (double)(spec.tv_nsec - start_timespec.tv_nsec) / 1000000000.0;
/*		current_time = tv.tv_sec + tv.tv_usec / 1000000.0 - start_time; */
		if (conv_write_idx != conv_send_idx) {
			/*  We have a pending event  */
			struct conv_record conv = conv_buf[conv_send_idx];
			if (conv.stamp <= current_time) {
				/*  Process this event  */
				/*  Note: outdata becomes the *last* output voltage, not this conv.outdata  */
				int outdata = conv.outdata;
				/*  Acquire  */
				conv.indata = conv_direct_read_nolock();
				conv.outdata = last_output;
				conv.stamp = current_time;
				if (outdata != -1) {
					/*  Send data  */
					conv_direct_write_nolock(outdata);
				}
				pthread_mutex_lock(&mutex);
				conv_buf[conv_send_idx] = conv;
				conv_send_idx = (conv_send_idx + 1) % CONV_BUFSIZE;
				pthread_mutex_unlock(&mutex);
				/*  No wait and proceed to next event  */
				wait_timestamp = -1.0;
			} else {
				/*  Wait  */
				const double ptime = 0.0001;  /*  Allow 100 us for processing time (may be different for different processor speed)  */
				wait_timestamp = conv.stamp - ptime;
			}
		} else {
			/*  No data; sleep for 5 ms and check again  */
			wait_timestamp = current_time + 0.005;
		}
		if (wait_timestamp > 0) {
			spec.tv_sec = start_timespec.tv_sec + floor(wait_timestamp);
			spec.tv_nsec = start_timespec.tv_nsec + (long)((wait_timestamp - floor(wait_timestamp)) * 1000000000.0);
			if (spec.tv_nsec > 1000000000) {
				spec.tv_sec += spec.tv_nsec / 1000000000;
				spec.tv_nsec = spec.tv_nsec % 1000000000;
			}
			clock_nanosleep(CLOCK_REALTIME, TIMER_ABSTIME, &spec, NULL);
		}
	}
	return NULL;
}

int
conv_init(int ch1, int speed1, int ch2, int speed2, int gpio)
{
	int n;
	if ((n = spi_setup(ch1, speed1, 0, 8)) != 0) {
		fprintf(stderr, "spi_setup for channel %d failed (%d).\n", ch1, n);
		return n;
	}
	if ((n = spi_setup(ch2, speed2, 0, 8)) != 0) {
		fprintf(stderr, "spi_setup for channel %d failed (%d).\n", ch2, n);
		return n;
	}
	gpio_setup();
	pinMode(gpio, 1);
	digitalWrite(gpio, 1);
	spi_ch1 = ch1;
	spi_ch2 = ch2;
	gpio_pin = gpio;
	pthread_mutex_init(&mutex, NULL);
	/*  Create a thread to handle electrochemistry:
	    We set high priority to keep the timings as precisely as possible  */
	{
		pthread_attr_t attr;
		struct sched_param param;
		pthread_attr_init(&attr);
		pthread_attr_setschedpolicy(&attr, SCHED_FIFO);
		pthread_attr_setinheritsched(&attr, PTHREAD_EXPLICIT_SCHED);
		sched_getparam(0, &param);
		param.sched_priority = sched_get_priority_max(SCHED_FIFO);
		pthread_attr_setschedparam(&attr, &param);
		if ((n = pthread_create(&th, &attr, thread_entry, NULL)) != 0) {
			fprintf(stderr, "pthread_create failed: %s\n", strerror(n));
			return -10;
		}
		pthread_attr_destroy(&attr);
	}
	return 0;
}

int
conv_quit(void)
{
	conv_state = 2;
	pthread_join(th, NULL);
	pthread_mutex_destroy(&mutex);
	return 0;
}

int
conv_reset(void)
{
	pthread_mutex_lock(&mutex);
	conv_state = 0;
	conv_write_idx = conv_read_idx = conv_send_idx = 0;
	pthread_mutex_unlock(&mutex);
}

int
conv_queue(struct conv_record *data)
{
	int retval = 0;
	pthread_mutex_lock(&mutex);
	if ((conv_write_idx + CONV_BUFSIZE - conv_read_idx) % CONV_BUFSIZE < CONV_BUFSIZE - 1) {
		struct conv_record *cp = conv_buf + conv_write_idx;
		*cp = *data;
		cp->indata = -1;
		conv_write_idx = (conv_write_idx + 1) % CONV_BUFSIZE;
	} else retval = -1;
	pthread_mutex_unlock(&mutex);
	return retval;
}

int
conv_start(void)
{
	pthread_mutex_lock(&mutex);
	clock_gettime(CLOCK_REALTIME, &start_timespec);
	conv_state = 1;
	pthread_mutex_unlock(&mutex);
	return 0;
}

int
conv_read(struct conv_record *data)
{
	int retval = 0;
	pthread_mutex_lock(&mutex);
	if (conv_send_idx != conv_read_idx) {
		struct conv_record *cp = conv_buf + conv_read_idx;
		*data = *cp;
		conv_read_idx = (conv_read_idx + 1) % CONV_BUFSIZE;
	} else retval = -1;
	pthread_mutex_unlock(&mutex);
	return retval;
}

int
conv_stop(void)
{
	conv_state = 0;
	return 0;
}
