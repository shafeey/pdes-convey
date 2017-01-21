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
  uint64_t  gvt[4];
  uint64_t  *cp_a0;
  uint64_t  *cp_a1;
  uint64_t  *cp_a2;
  uint64_t  *cp_a3;
  uint64_t  sim_end_time;
  uint64_t  num_init_events = 64;
  long size = 8;

  // check command line args
  if (argc == 1) {
    sim_end_time = 1000;		// default size
    printf("Simulation will run until GVT = %ld\n", sim_end_time);
    fflush(stdout);
  } else if (argc == 2) {
    size = atoi(argv[1]);
    if (size > 0) {
      printf("Simulation will run until GVT = %ld\n", sim_end_time);
      fflush(stdout);
    } else {
      usage (argv[0]);
      return 0;
    }
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

  uint64_t args[4];
  args[0] = (uint64_t) cp_a0; 
  args[1] = sim_end_time;
  args[2] = num_init_events; 
  args[3] = (uint64_t) cp_a3;
  
  wdm_dispatch_t ds;
  memset((void *)&ds, 0, sizeof(ds));
  for (i=0; i<4; i++) {
    ds.ae[i].aeg_ptr_s = args;
    ds.ae[i].aeg_cnt_s = 2;
    ds.ae[i].aeg_base_s = 0;
    ds.ae[i].aeg_ptr_r = &gvt[i];
    ds.ae[i].aeg_cnt_r = 1;
    ds.ae[i].aeg_base_r = 4;
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

  printf("Returned gvt = %lld\n", gvt[0]);

  return 0;
}

// Print usage message and exit with error.
void
usage (char* p)
{
    printf("usage: %s [count (default 100)] \n", p);
    exit (1);
}


