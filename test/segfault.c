// Copyright 2025 Test Program
#include <stdio.h>

int main() {
  int *ptr = NULL;
  printf("About to segfault...\n");
  *ptr = 42;
  return 0;
}
