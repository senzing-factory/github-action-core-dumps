#include <stdio.h>

int main()
{
  int *ptr = NULL;
  printf("About to segfault...\n");
  *ptr = 42; // Dereference NULL pointer
  return 0;
}
