# ModGenSym

struct ModGenSym <: Function
    mod::Symbol
    x::Base.RefValue{Int}
end
const globalmgsref = IdDict{Symbol,ModGenSym}()
function ModGenSym(x::Symbol)
    get!(() -> ModGenSym(x, Ref(0)), globalmgsref, x)
end
(mgs::ModGenSym)(x::Symbol) = Symbol(x, "##", mgs.x[] += 1)

# Other

function makeexpr(head, args)
    x = Expr(head)
    x.args = args
    return x
end
