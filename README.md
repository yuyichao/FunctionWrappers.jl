# FunctionWrappers.jl: Type stable and efficient wrapper of arbitrary functions

[![Build Status](https://github.com/yuyichao/FunctionWrappers.jl/workflows/CI/badge.svg)](https://github.com/yuyichao/FunctionWrappers.jl/actions)
[![Build Status](https://travis-ci.org/yuyichao/FunctionWrappers.jl.svg?branch=master)](https://travis-ci.org/yuyichao/FunctionWrappers.jl)
[![Build status](https://ci.appveyor.com/api/projects/status/mgearlsjllu4mdtd/branch/master?svg=true)](https://ci.appveyor.com/project/yuyichao/functionwrappers-jl/branch/master)
[![codecov.io](http://codecov.io/github/yuyichao/FunctionWrappers.jl/coverage.svg?branch=master)](http://codecov.io/github/yuyichao/FunctionWrappers.jl?branch=master)

Proof of principle implementation of [JuliaLang/julia#13984](https://github.com/JuliaLang/julia/issues/13984).

## Limitations

1. Does not handle more than 128 arguments without jlcall wrapper

    128 is an arbitrary limit. Should be high enough for all practical cases

2. Does not support vararg argument types

3. Wrapper Object cannot be serialized by `dump.c` and therefore the
   precompilation of `FunctionWrappers` is done using a runtime branch
   and by making the wrapper type mutable.

## Compared to `@cfunction`

This does not require LLVM trampoline support, which is not currently supported by LLVM
on all the architectures julia runs on ([JuliaLang/julia#27174](https://github.com/JuliaLang/julia/issues/27174)).
Other than this issue `@cfunction` should cover all of the use cases.

## Simple Usage Example

```julia
using FunctionWrappers
import FunctionWrappers: FunctionWrapper

# For a function that sends (x1::T1, x2::T2, ...) -> ::TN, you use
# a FunctionWrapper{TN, Tuple{T1, T2, ...}}.
struct TypeStableStruct 
  fun::FunctionWrapper{Float64, Tuple{Float64, Float64}}
  second_arg::Float64
end

evaluate_strfun(str, arg) = str.fun(arg, str.second_arg)

example = TypeStableStruct(hypot, 1.0)

@code_warntype evaluate_strfun(example, 1.5) # all good
```

