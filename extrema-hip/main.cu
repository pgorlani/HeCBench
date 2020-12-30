// Copyright (c) 2019-2020, NVIDIA CORPORATION.
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <stdio.h>
#include <stdlib.h>
#include <hip/hip_runtime.h>

__host__ __device__ __forceinline__ void clip_plus( const bool &clip, const int &n, int &plus ) {
  if ( clip ) {
    if ( plus >= n ) {
      plus = n - 1;
    }
  } else {
    if ( plus >= n ) {
      plus -= n;
    }
  }
}

__host__ __device__ __forceinline__ void clip_minus( const bool &clip, const int &n, int &minus ) {
  if ( clip ) {
    if ( minus < 0 ) {
      minus = 0;
    }
  } else {
    if ( minus < 0 ) {
      minus += n;
    }
  }
}

///////////////////////////////////////////////////////////////////////////////
//                          BOOLRELEXTREMA 1D                                //
///////////////////////////////////////////////////////////////////////////////

  template<typename T>
__global__ void relextrema_1D( const int  n,
    const int  order,
    const bool clip,
    const T *__restrict__ inp,
    bool *__restrict__ results)
{

  const int tx = blockIdx.x * blockDim.x + threadIdx.x;
  const int stride = blockDim.x * gridDim.x;

  for ( int tid = tx; tid < n; tid += stride ) {

    const T data = inp[tid];
    bool    temp = true;

    for ( int o = 1; o < ( order + 1 ); o++ ) {
      int plus = tid + o;
      int minus = tid - o;

      clip_plus( clip, n, plus );
      clip_minus( clip, n, minus );

      temp &= data > inp[plus];
      temp &= data >= inp[minus];
    }
    results[tid] = temp;
  }
}

  template<typename T>
void cpu_relextrema_1D( const int  n,
    const int  order,
    const bool clip,
    const T *__restrict__ inp,
    bool *__restrict__ results)
{

  for ( int tid = 0; tid < n; tid++ ) {

    const T data = inp[tid];
    bool    temp = true;

    for ( int o = 1; o < ( order + 1 ); o++ ) {
      int plus = tid + o;
      int minus = tid - o;

      clip_plus( clip, n, plus );
      clip_minus( clip, n, minus );

      temp &= data > inp[plus];
      temp &= data >= inp[minus];
    }
    results[tid] = temp;
  }
}


  template<typename T>
__global__ void relextrema_2D( const int  in_x,
    const int  in_y,
    const int  order,
    const bool clip,
    const int  axis,
    const T *__restrict__ inp,
    bool *__restrict__ results) 
{

  const int ty = blockIdx.x * blockDim.x + threadIdx.x;
  const int tx = blockIdx.y * blockDim.y + threadIdx.y;

  if ( ( tx < in_y ) && ( ty < in_x ) ) {
    int tid = tx * in_x + ty ;

    const T data = inp[tid] ;
    bool    temp = true ;

    for ( int o = 1; o < ( order + 1 ); o++ ) {

      int plus;
      int minus;

      if ( axis == 0 ) {
        plus  = tx + o;
        minus = tx - o;

        clip_plus( clip, in_y, plus );
        clip_minus( clip, in_y, minus );

        plus  = plus * in_x + ty;
        minus = minus * in_x + ty;
      } else {
        plus  = ty + o;
        minus = ty - o;

        clip_plus( clip, in_x, plus );
        clip_minus( clip, in_x, minus );

        plus  = tx * in_x + plus;
        minus = tx * in_x + minus;
      }

      temp &= data > inp[plus] ;
      temp &= data >= inp[minus] ;
    }
    results[tid] = temp;
  }
}

template<typename T>
void cpu_relextrema_2D( const int  in_x,
    const int  in_y,
    const int  order,
    const bool clip,
    const int  axis,
    const T *__restrict__ inp,
    bool *__restrict__ results) 
{
  for (int tx = 0; tx < in_y; tx++)
    for (int ty = 0; ty < in_x; ty++) {

      int tid = tx * in_x + ty ;

      const T data = inp[tid] ;
      bool    temp = true ;

      for ( int o = 1; o < ( order + 1 ); o++ ) {

        int plus;
        int minus;

        if ( axis == 0 ) {
          plus  = tx + o;
          minus = tx - o;

          clip_plus( clip, in_y, plus );
          clip_minus( clip, in_y, minus );

          plus  = plus * in_x + ty;
          minus = minus * in_x + ty;
        } else {
          plus  = ty + o;
          minus = ty - o;

          clip_plus( clip, in_x, plus );
          clip_minus( clip, in_x, minus );

          plus  = tx * in_x + plus;
          minus = tx * in_x + minus;
        }

        temp &= data > inp[plus] ;
        temp &= data >= inp[minus] ;
      }
      results[tid] = temp;
    }
}

template <typename T>
void test_1D (const int length, const int order) {
  T* x = (T*) malloc (sizeof(T)*length);
  for (int i = 0; i < length; i++)
    x[i] = rand() % length;
  
  bool* cpu_r = (bool*) malloc (sizeof(bool)*length);
  bool* gpu_r = (bool*) malloc (sizeof(bool)*length);

  T* d_x;
  bool *d_result;
  hipMalloc((void**)&d_x, length*sizeof(T));
  hipMemcpy(d_x, x, length*sizeof(T), hipMemcpyHostToDevice);
  hipMalloc((void**)&d_result, length*sizeof(bool));

  dim3 grids ((length+255)/256);
  dim3 threads (256);

  for (int n = 0; n < 100; n++)
    hipLaunchKernelGGL(HIP_KERNEL_NAME(relextrema_1D<T>), dim3(grids), dim3(threads), 0, 0, length, order, true, d_x, d_result);

  hipMemcpy(gpu_r, d_result, length*sizeof(bool), hipMemcpyDeviceToHost);

  cpu_relextrema_1D<T>(length, order, true, x, cpu_r);

  int error = 0;
  for (int i = 0; i < length; i++)
    if (cpu_r[i] != gpu_r[i]) {
      error = 1; 
      break;
    }

  hipFree(d_x);
  hipFree(d_result);
  free(x);
  free(cpu_r);
  free(gpu_r);
  if (error) printf("1D test: FAILED\n");
}

template <typename T>
void test_2D (const int length_x, const int length_y, const int order) {
  const int length = length_x * length_y;
  T* x = (T*) malloc (sizeof(T)*length);
  for (int i = 0; i < length; i++)
    x[i] = rand() % length;
  
  bool* cpu_r = (bool*) malloc (sizeof(bool)*length);
  bool* gpu_r = (bool*) malloc (sizeof(bool)*length);

  T* d_x;
  bool *d_result;
  hipMalloc((void**)&d_x, length*sizeof(T));
  hipMemcpy(d_x, x, length*sizeof(T), hipMemcpyHostToDevice);
  hipMalloc((void**)&d_result, length*sizeof(bool));

  dim3 grids ((length_x+15)/16, (length_y+15)/16);
  dim3 threads (16, 16);

  for (int n = 0; n < 100; n++)
    hipLaunchKernelGGL(relextrema_2D, dim3(grids), dim3(threads), 0, 0, length_x, length_y, 1, true, 1, d_x, d_result);

  hipMemcpy(gpu_r, d_result, length*sizeof(bool), hipMemcpyDeviceToHost);

  cpu_relextrema_2D(length_x, length_y, 1, true, 1, x, cpu_r);

  int error = 0;
  for (int i = 0; i < length; i++)
    if (cpu_r[i] != gpu_r[i]) {
      error = 1; 
      break;
    }

  hipFree(d_x);
  hipFree(d_result);
  free(x);
  free(cpu_r);
  free(gpu_r);
  if (error) printf("2D test: FAILED\n");
}

int main() {

  for (int order = 1; order <= 128; order = order * 2) {
    test_1D<int>(1000000, order);
    test_1D<long>(1000000, order);
    test_1D<float>(1000000, order);
    test_1D<double>(1000000, order);
  }

  for (int order = 1; order <= 128; order = order * 2) {
    test_2D<int>(1000, 1000, order);
    test_2D<long>(1000, 1000, order);
    test_2D<float>(1000, 1000, order);
    test_2D<double>(1000, 1000, order);
  }

  return 0;
}

