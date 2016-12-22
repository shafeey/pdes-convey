#include <convey/usr/cny_comp.h>
#include <ctype.h>
#include <stdlib.h>
#include <string.h>

#undef DEBUG

typedef unsigned long long uint64;
extern long cpPhold();

int main(int argc, char *argv[])
{
  long i;
  uint64 gvt=0;
  uint64  *cp_a1;
  long size = 8;

  // Get personality signature
  // The "pdk" personality is the PDK sample vadd personality
  cny_image_t        sig2;
  cny_image_t        sig;
  int stat;
  if (cny_get_signature)
    cny_get_signature("pdk", &sig, &sig2, &stat);
  else 
    fprintf(stderr,"***ERROR:  cny_get_signature not found\n");

  if (stat) {
    printf("***ERROR:  cny_get_signature() Failure: %d\n", stat);
    exit(1);
  }

  // check interleave
  // this example requires binary interleave
  if (cny_cp_interleave() == CNY_MI_3131) {
    printf("***ERROR:  interleave set to 3131, this personality requires binary interleave\n");
    exit (1);
  }
  
  // Allocate memory on coprocessor
  if (cny_cp_malloc)  {
    cp_a1 = (uint64 *) (cny_cp_malloc)(size*64);
	printf("Address passed to CAE: %p\n", cp_a1);
  }
  else 
    printf("malloc failed\n");


  // phold copcall
  gvt = l_copcall_fmt(sig, cpPhold, "A", cp_a1);
  printf("Returned gvt = %d\n", gvt);

  return 0;
}
