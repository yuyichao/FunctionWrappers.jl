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
                   """), Cvoid, Tuple{Bool}, v)
end

is_singleton(@nospecialize(T)) = isdefined(T, :instance)

# Convert return type and generates cfunction signatures
Base.@pure map_rettype(T) =
    (isbitstype(T) || T === Any || is_singleton(T)) ? T : Ref{T}
Base.@pure function map_cfunc_argtype(T)
    if is_singleton(T)
        return Ref{T}
    end
    return (isbitstype(T) || T === Any) ? T : Ref{T}
end
Base.@pure function map_argtype(T)
    if is_singleton(T)
        return Any
    end
    return (isbitstype(T) || T === Any) ? T : Any
end
Base.@pure get_cfunc_argtype(Obj, Args) =
    Tuple{Ref{Obj}, (map_cfunc_argtype(Arg) for Arg in Args.parameters)...}

@generated function make_cfunction(obj::objT, ::Type{Ret}, ::Type{Args}) where {objT,Ret,Args}
    :(@cfunction(
        $(Expr(:$, obj)),
        map_rettype(Ret),
        (Ref{objT}, $([:(map_cfunc_argtype($Arg)) for Arg in Args.parameters]...))))
end

mutable struct FunctionWrapper{Ret,Args<:Tuple}
    ptr::Ptr{Cvoid}
    objptr::Ptr{Cvoid}
    obj
    objT
    function FunctionWrapper{Ret,Args}(obj::objT) where {Ret,Args,objT}
        objref = Base.cconvert(Ref{objT}, obj)
        ptr = make_cfunction(obj, Ret, Args)
        new{Ret,Args}(ptr, Base.unsafe_convert(Ref{objT}, objref), objref, objT)
    end

    FunctionWrapper{Ret,Args}(obj::FunctionWrapper{Ret,Args}) where {Ret,Args} = obj
end

Base.convert(::Type{T}, obj) where {T<:FunctionWrapper} = T(obj)
Base.convert(::Type{T}, obj::T) where {T<:FunctionWrapper} = obj

@noinline function reinit_wrapper(f::FunctionWrapper{Ret,Args}) where {Ret,Args}
    objref = f.obj
    objT = f.objT
    ptr = make_cfunction(obj, Ret, Args)
    f.ptr = ptr
    f.objptr = Base.unsafe_convert(Ref{objT}, objref)
    return ptr
end

@generated function do_ccall(f::FunctionWrapper{Ret,Args}, args::Args) where {Ret,Args}
    # Has to be generated since the arguments type of `ccall` does not allow
    # anything other than tuple (i.e. `@pure` function doesn't work).
    quote
        Base.@_inline_meta
        ptr = f.ptr
        if ptr == C_NULL
            # For precompile support
            ptr = reinit_wrapper(f)
        end
        assume(ptr != C_NULL)
        objptr = f.objptr
        ccall(ptr, $(map_rettype(Ret)),
              (Ptr{Cvoid}, $((map_argtype(Arg) for Arg in Args.parameters)...)),
              objptr, $((:(args[$i]) for i in 1:length(Args.parameters))...))
    end
end

@inline (f::FunctionWrapper)(args...) = do_ccall(f, args)

# Testing only
const identityAnyAny = FunctionWrapper{Any,Tuple{Any}}(identity)

end
