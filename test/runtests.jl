#!/usr/bin/julia -f

import FunctionWrappers
import FunctionWrappers: FunctionWrapper
using Base.Test

if VERSION >= v"0.6.0"
    # Can in princeple be lower but 0.6 doesn't warn on this so it doesn't matter
    eval(parse("struct CallbackF64 f::FunctionWrapper{Float64,Tuple{Int}} end"))
else
    eval(parse("immutable CallbackF64 f::FunctionWrapper{Float64,Tuple{Int}} end"))
end
(cb::CallbackF64)(v) = cb.f(v)
gen_closure(x) = y->x + y

@testset "As field" begin
    f1 = @inferred CallbackF64(identity)
    f2 = @inferred CallbackF64(sin)
    f3 = @inferred CallbackF64(gen_closure(2))
    @test typeof(f1) == typeof(f2) == typeof(f3)
    @test @inferred(f1(1)) === 1.0
    @test @inferred(f2(1)) === sin(1)
    @test @inferred(f3(1)) === 3.0
end

const F64AnyFunc = FunctionWrapper{Float64,Tuple{Any}}

@testset "Any input" begin
    f1 = @inferred F64AnyFunc(identity)
    f2 = @inferred F64AnyFunc(gen_closure(2))
    @test typeof(f1) === typeof(f2)
    @test @inferred(f1(1)) === 1.0
    @test @inferred(f1(1.0)) === 1.0
    @test @inferred(f1(1f0)) === 1.0
    @test @inferred(f2(1)) === 3.0
end

const F64F64Func = FunctionWrapper{Float64,Tuple{Float64}}

@testset "Convert" begin
    f1 = @inferred F64F64Func(sin)
    f2 = @inferred F64F64Func(f1)
    f3 = @inferred convert(F64F64Func, f1)
    @test f1 === f2
    @test f1 === f3
end

const NumberAnyFunc = FunctionWrapper{Number,Tuple{Any}}

@testset "Abstract Return" begin
    @test NumberAnyFunc(sin)(1) === sin(1)
    @test NumberAnyFunc(identity)(1) === 1
end

@testset "Precompile" begin
    @test FunctionWrappers.identityAnyAny(1) === 1
end

@testset "Void" begin
    identityVoidVoid = FunctionWrapper{Void,Tuple{Void}}(identity)
    @test identityVoidVoid(nothing) === nothing
    f1 = (a, b)->b
    fIntVoidInt = FunctionWrapper{Int,Tuple{Void,Int}}(f1)
    @test fIntVoidInt(nothing, 1) === 1
end
