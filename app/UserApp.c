#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <wdm_user.h>
#include <errno.h>

#undef DEBUG

extern long cpPhold();
void usage (char *);

int main(int argc, char *argv[])
{
  long i;
  uint64_t  gvt;
  uint64_t  total_cycles;
  uint64_t  total_events;
  uint64_t  total_stalls;
  uint64_t  total_antimsg;
  uint64_t  total_qconf;
  uint64_t  avg_mem_time;
  uint64_t  avg_proc_time;

  
  uint64_t  *cp_a0;
  uint64_t  *cp_a1;
  uint64_t  *cp_a2;
  uint64_t  *cp_a3;
  uint64_t  sim_end_time;
  uint64_t  num_init_events = 64;
  uint64_t num_LP = 64;
  uint64_t num_mem_access = 0;
  
  uint64_t report[64];
  long size = 8;

  // check command line args
  if (argc == 1) {
    sim_end_time = 1000;		// default size
    printf("Simulation will run until GVT = %lld\n", (long long) sim_end_time);
    fflush(stdout);
  } else if (argc == 2) {
    sim_end_time = atoi(argv[1]);
    if (sim_end_time > 0) {
      printf("Simulation will run until GVT = %lld\n", (long long) sim_end_time);
      fflush(stdout);
    } else {
      usage (argv[0]);
      return 0;
    }
  }
  else if (argc == 5){
	      sim_end_time = atoi(argv[1]);
    num_init_events = atoi(argv[2]);
	num_LP = atoi(argv[3]);
	num_mem_access = atoi(argv[4]);
  }
  else {
    usage (argv[0]);
    return 0;
  }
  
  // Reserve and attach to the coprocessor
  // The "pdk" personality is the PDK sample vadd personality
  wdm_coproc_t m_coproc = WDM_INVALID;
  m_coproc = wdm_reserve(WDM_CPID_ANY, NULL);

  if (m_coproc == WDM_INVALID) {
      fprintf(stderr, "Unable to reserve coprocessor\n");
      return -1;
  }

  char *name = "pdk";
  if (wdm_attach(m_coproc, name)) {
      fprintf(stderr, "Unable to attach signature \"%s\"\n", name);
      fprintf(stderr, " Please verify that the personality is installed in");
      fprintf(stderr, " /opt/convey/personalities or CNY_PERSONALITY_PATH is set.\n");
      return -1;
  }

  // Allocate memory on coprocessor
  wdm_posix_memalign(m_coproc, (void**)&cp_a0, 64, size*128);
  printf("Address passed to CAE: %p\n", cp_a0);
  wdm_posix_memalign(m_coproc, (void**)&cp_a1, 64, size*128);
  printf("Address passed to CAE: %p\n", cp_a1);
  wdm_posix_memalign(m_coproc, (void**)&cp_a2, 64, size*128);
  printf("Address passed to CAE: %p\n", cp_a2);
  wdm_posix_memalign(m_coproc, (void**)&cp_a3, 64, size*128);
  printf("Address passed to CAE: %p\n", cp_a3);

  
  num_LP = num_LP-1;
  
  uint64_t args[4];
  args[0] = (uint64_t) cp_a0; 
  args[1] = sim_end_time;
  args[2] = num_init_events; 
  args[3] = num_LP | (num_mem_access << 16);
    
  wdm_dispatch_t ds;
  memset((void *)&ds, 0, sizeof(ds));
  for (i=0; i<4; i++) {
    ds.ae[i].aeg_ptr_s = args;
    ds.ae[i].aeg_cnt_s = 4;
    ds.ae[i].aeg_base_s = 0;
    ds.ae[i].aeg_ptr_r = &report[i*16];
    ds.ae[i].aeg_cnt_r = 8;
    ds.ae[i].aeg_base_r = 5;
  }

  if (wdm_dispatch(m_coproc, &ds)) {
    perror("dispatch error");
    exit(-1);
  }

  int stat = 0;
  while (!(stat = wdm_dispatch_status(m_coproc)))
      usleep(10000);

  if (stat < 0) {
    perror("dispatch status error");
    exit(-1);
  }

  gvt = report[0];
  total_cycles = report[1];
  total_events = report[2];
  total_stalls = report[3];
  total_antimsg = report[4];
  total_qconf = report[5];
  avg_proc_time = report[6];
  avg_mem_time = report[7];

  printf("Returned GVT = %lld\n", (long long) gvt);
  printf("Total cycles = %lld\n", (long long) total_cycles);
  printf("Total events = %lld\n", (long long) total_events);
  printf("Total antimessages = %lld\n", (long long) total_antimsg);
  printf("Total stall cycles = %lld\n", (long long) total_stalls);
  printf("Contention for queue = %lld\n", (long long) total_qconf);
  printf("Total active time per core = %lld\n", (long long) avg_proc_time);
  printf("Total memory access time per core = %lld\n", (long long) avg_mem_time);


  return 0;
}

// Print usage message and exit with error.
void
usage (char* p)
{
    printf("usage: %s [count (default 100)] \n", p);
    exit (1);
}


