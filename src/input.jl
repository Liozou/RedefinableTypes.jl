# First pass on the input expression: extract type declarations

function istypedeclaration(@nospecialize x)
    x isa Expr || return false
    h = (x::Expr).head
    return (h === :struct) | (h === :abstract) | (h === :primitive)
end

function collect_declarations!(declarations::Vector{TypeDeclaration},
                               otherexpressions::Vector{Union{Nothing,Some{Any}}},
                               @nospecialize(expr))
    if expr isa Expr
        if expr.head === :block
            for a in expr.args
                collect_declarations!(declarations, otherexpressions, a)
            end
        elseif istypedeclaration(expr)
            decl = TypeDeclaration(expr)
            push!(declarations, decl)
            push!(otherexpressions, nothing)
        else
            # potentialalias = tryTypeAlias(expr)
            # if potentialalias isa TypeAlias
            #     push!(declarations, potentialalias)
            #     push!(otherexpressions, nothing)
            # else
            #     push!(otherexpressions, Some{Any}(expr))
            # end
            push!(otherexpressions, Some{Any}(expr))
        end
    elseif !(expr isa Nothing)
        push!(otherexpressions, Some{Any}(expr))
    end
    return declarations, otherexpressions
end

collect_declarations(expr::Expr) = collect_declarations!(TypeDeclaration[], Union{Nothing,Some{Any}}[], expr)
