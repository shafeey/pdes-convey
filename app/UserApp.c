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
  uint64_t  *gvt;
  uint64_t  *cp_a1;
  long size = 8;
  
  // long size;
  // uint64_t *a1, *a2, *a3;
  // uint64_t *cp_a1, *cp_a2, *cp_a3;
  // uint64_t ae_sum[4];
  // uint64_t act_sum=0;
  // uint64_t exp_sum=0;

  // // check command line args
  // if (argc == 1) {
    // size = 100;		// default size
    // printf("Running UserApp.exe with size = %ld\n", size);
    // fflush(stdout);
  // } else if (argc == 2) {
    // size = atoi(argv[1]);
    // if (size > 0) {
      // printf("Running UserApp.exe with size = %ld\n", size);
      // fflush(stdout);
    // } else {
      // usage (argv[0]);
      // return 0;
    // }
  // }
  // else {
    // usage (argv[0]);
    // return 0;
  // }

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

  //-------------------------------------------------------
  // For max performance, fill arrays on host, then use
  // datamover to copy data to coprocessor
  //-------------------------------------------------------

  // Allocate memory on host
  a1 = (uint64_t *) (malloc)(size*8);
  a2 = (uint64_t *) (malloc)(size*8);
  a3 = (uint64_t *) (malloc)(size*8);

  // Allocate memory on coprocessor
  wdm_posix_memalign(m_coproc, (void**)&cp_a1, 64, size*128);
  printf("Address passed to CAE: %p\n", cp_a1);

  // vector add function dispatch
  uint64_t args[4];
  args[0] = (uint64_t) cp_a1; 
  args[1] = (uint64_t) cp_a2; 
  args[2] = (uint64_t) cp_a3; 
  args[3] = size;
  
  wdm_dispatch_t ds;
  memset((void *)&ds, 0, sizeof(ds));
  for (i=0; i<1; i++) {
    ds.ae[i].aeg_ptr_s = cp_a1;
    ds.ae[i].aeg_cnt_s = 1;
    ds.ae[i].aeg_base_s = 0;
    ds.ae[i].aeg_ptr_r = gvt;
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

  printf("Returned gvt = %d\n", *gvt);

  return 0;
}

// Print usage message and exit with error.
void
usage (char* p)
{
    printf("usage: %s [count (default 100)] \n", p);
    exit (1);
}

