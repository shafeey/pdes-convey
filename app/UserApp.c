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


  // phold copcall
  gvt = l_copcall_fmt(sig, cpPhold, "");
  printf("Returned gvt = %d\n", gvt);

  return 0;
}
