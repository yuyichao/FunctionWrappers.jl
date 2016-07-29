#!/usr/bin/julia -f

import FunctionWrappers: FunctionWrapper
using Base.Test

immutable Callback
    f::FunctionWrapper{Float64,Tuple{Int}}
end

@test @inferred(Callback(identity).f(1)) === 1.0
@test @inferred(Callback(sin).f(1)) === sin(1)

typealias F64Func FunctionWrapper{Float64,Tuple{Any}}

@test @inferred(F64Func(identity)(1)) === 1.0
@test @inferred(F64Func(identity)(1.0)) === 1.0
@test @inferred(F64Func(identity)(1f0)) === 1.0
