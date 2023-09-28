module RedefinableTypes

include("utils.jl")
include("types.jl")
include("input.jl")
include("identification.jl")
include("replacement.jl")
include("constructors.jl")
include("output.jl")

⋆(::Type{T}) where {T} = T

"""
    make_redefinable(expr::Expr, mgs::ModGenSym)

Entry point to @redefine
"""
function make_redefinable(expr::Expr, mgs::ModGenSym)
    declarations, expressions = collect_declarations(expr)
    newdeclarations = [make_redefinable_declaration(decl, mgs) for decl in declarations]
    (newdeclarations, expressions)
end


macro redefinable(expr)
    mgs = ModGenSym(Symbol(__module__))
    newdeclarations, expressions = make_redefinable(expr, mgs)
    ret = Expr(:block)
    j = 1
    for e in expressions
        if e isa Nothing
            push!(ret.args, newdeclarations[j])
            j += 1
        else
            push!(ret.args, something(e))
        end
    end
    esc(ret)
end


for s in names(RedefinableTypes; all=true)
    (s === :eval || s === :include || startswith(String(s), '#')) && continue
    @eval export $s
end

end