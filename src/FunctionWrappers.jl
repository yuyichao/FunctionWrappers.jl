#!/usr/bin/julia

__precompile__(true)

module FunctionWrappers

# Used to bypass NULL check
@inline function assume(v::Bool)
    Base.llvmcall(("declare void @llvm.assume(i1)",
                   """
                   %v = trunc i8 %0 to i1
                   call void @llvm.assume(i1 %v)
                   ret void
                   """), Void, Tuple{Bool}, v)
end

is_singleton(T::ANY) = isdefined(T, :instance)

# Convert return type and generates cfunction signatures
Base.@pure map_rettype(T) =
    (isbits(T) || T === Any || is_singleton(T)) ? T : Ref{T}
Base.@pure function map_cfunc_argtype(T)
    if is_singleton(T)
        return Ref{T}
    end
    return (isbits(T) || T === Any) ? T : Ref{T}
end
Base.@pure function map_argtype(T)
    if is_singleton(T)
        return Any
    end
    return (isbits(T) || T === Any) ? T : Any
end
Base.@pure get_cfunc_argtype(Obj, Args) =
    Tuple{Ref{Obj}, (map_cfunc_argtype(Arg) for Arg in Args.parameters)...}

# Call wrapper since `cfunction` does not support non-function
# or closures
if VERSION >= v"0.6.0"
    # Can in princeple be lower but 0.6 doesn't warn on this so it doesn't matter
    include_string("struct CallWrapper{Ret} <: Function end")
else
    include_string("immutable CallWrapper{Ret} <: Function end")
end
(::CallWrapper{Ret}){Ret}(f, args...)::Ret = f(args...)

# Specialized wrapper for
for nargs in 0:128
    @eval (::CallWrapper{Ret}){Ret}(f, $((Symbol("arg", i) for i in 1:nargs)...))::Ret =
        f($((Symbol("arg", i) for i in 1:nargs)...))
end

let ex = if VERSION >= v"0.6.0"
    # Can in princeple be lower but 0.6 doesn't warn on this so it doesn't matter
    parse("mutable struct FunctionWrapper{Ret,Args<:Tuple} end")
else
    parse("type FunctionWrapper{Ret,Args<:Tuple} end")
end
    ex.args[3] = quote
        ptr::Ptr{Void}
        objptr::Ptr{Void}
        obj
        objT
        function (::Type{FunctionWrapper{Ret,Args}}){Ret,Args,objT}(obj::objT)
            objref = Base.cconvert(Ref{objT}, obj)
            new{Ret,Args}(cfunction(CallWrapper{Ret}(), map_rettype(Ret),
                                    get_cfunc_argtype(objT, Args)),
                          Base.unsafe_convert(Ref{objT}, objref), objref, objT)
        end
        (::Type{FunctionWrapper{Ret,Args}}){Ret,Args}(obj::FunctionWrapper{Ret,Args}) = obj
    end
    eval(ex)
end

Base.convert{T<:FunctionWrapper}(::Type{T}, obj) = T(obj)
Base.convert{T<:FunctionWrapper}(::Type{T}, obj::T) = obj

@noinline function reinit_wrapper{Ret,Args}(f::FunctionWrapper{Ret,Args})
    objref = f.obj
    objT = f.objT
    ptr = cfunction(CallWrapper{Ret}(), map_rettype(Ret),
                    get_cfunc_argtype(objT, Args))
    f.ptr = ptr
    f.objptr = Base.unsafe_convert(Ref{objT}, objref)
    return ptr
end

@generated function do_ccall{Ret,Args}(f::FunctionWrapper{Ret,Args}, args::Args)
    # Has to be generated since the arguments type of `ccall` does not allow
    # anything other than tuple (i.e. `@pure` function doesn't work).
    quote
        $(Expr(:meta, :inline))
        ptr = f.ptr
        if ptr == C_NULL
            # For precompile support
            ptr = reinit_wrapper(f)
        end
        assume(ptr != C_NULL)
        objptr = f.objptr
        ccall(ptr, $(map_rettype(Ret)),
              (Ptr{Void}, $((map_argtype(Arg) for Arg in Args.parameters)...)),
              objptr, $((:(args[$i]) for i in 1:length(Args.parameters))...))
    end
end

@inline (f::FunctionWrapper)(args...) = do_ccall(f, args)

# Testing only
const identityAnyAny = FunctionWrapper{Any,Tuple{Any}}(identity)

end
