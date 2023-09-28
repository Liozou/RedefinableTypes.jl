# RedefinableTypes

This Julia package provides the `@redefinable` macro which can be put in front of a type.
This allows redefining the type without having to start a new Julia session.

See also [RedefStructs.jl](https://federicostra.github.io/RedefStructs.jl/stable/) for
another package that aimed for the same kind of feature.

Example syntax:

In a file `test.jl`:

```julia
using RedefinableTypes

@redefinable struct Foo{T,N}
    x::T
end
```

In your main Julia session:

```julia
julia> using Revise

julia> includet("test.jl")

julia> Foo([3, 6]) # whoops, we made a mistake in the definition of Foo
ERROR: MethodError: no method matching Foo(::Vector{Int64})
Stacktrace:
 [1] top-level scope
   @ REPL[3]:1
```

Go back to your file `test.jl` and fix the definition of `Foo` into

```julia
@redefinable struct Foo{T,N}
    x::Array{T,N}
end
```

And back to your session:

```julia
julia> Foo([3, 6])
var"Foo##2"{Int64, 1}([3, 6])
```

The name `var"Foo##2"` corresponds to the actual type with the given definition for `Foo`,
which can be directly accessed as `⋆Foo`, where `⋆` can be written by typing `\star<TAB>`.

As a consequence, `Foo` is not directly the required type. It is actually defined as an
abstract supertype of the actual type `var"Foo##2"`.
If it is used as a parameter for other types, such as `Vector{Foo}`, it should be written
`Vector{⋆Foo}`.
Using `Vector{Foo}` instead of `Vector{⋆Foo}` should generally not change the correctness
of the code, although it will impact performance.

If used with other type-modifying macros such as `@kwdef`, use `@redefinable` as the
outermost macro.

Current limitations:

- It is still impossible to change the declared supertype.
- It is still impossible to change the declared type parameters (even their name).
