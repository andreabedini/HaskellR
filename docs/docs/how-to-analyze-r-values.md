---
title: How to analyze R values in Haskell
id: how-to-analyze-r-values
---

## Pattern matching on views

In order to avoid unnecessary copying or other overhead every time
code crosses the boundary to/from R and Haskell, `inline-r` opts for
the strategy of representing R values exactly as R itself does.
However, R values cannot be pattern matched upon directly, since they
do not share the same representation as values of algebraic datatypes
in Haskell. Regardless, R values can still be deconstructed and
pattern matched, provided a *view function* constructing a *view* of
any given R value as an algebraic datatype. `inline-r` provides one
such view function (in the `Language.R.HExp` module):

~~~ haskell
hexp :: SEXP s a -> HExp a
~~~

The `HExp` datatype is a *view type* for `SEXP`. Matching on a value
of type `HExp a` is an alternative to using accessor functions to gain
access to each field of the in-memory `SEXP` structure. The `HExp`
datatype offers a view that exposes exactly what accessor functions
would: it is a one-level unfolding of `SEXP`. See the
[inline-r internals](internal-structures.html) document for further
justifications for using one-level unfoldings and their relevance for
performance.

We have for example that:

~~~ haskell
hexp H.nilValue == Nil
hexp (mkSEXP ([2, 3] :: [Double])) == Real (fromList ([2, 3] :: [Double]))
~~~

Where `H.nilValue` is the result of evaluating `[r| NULL |]`

Using a language extension known as `ViewPatterns`, we can use `hexp`
to examine an expression to any depth rather compactly. For instance:

~~~ haskell
f (hexp -> Real xs) = _
f (hexp -> Lang rator (hexp -> List rand1 (hexp -> List rand2 _ _) _) = _
f (hexp -> Closure args body@(hexp -> Lang _ _) env) = _
~~~

### R values and side effects

As explained previously, values of type `SEXP s a` are in fact pointers
to structures stored on the R heap, an area of memory managed by the
R interpreter. As such, one must take heed of the following two
observations when using a pure function such as `hexp` to dereference
such pointers.

First, just like regular Haskell values are allocated on the GHC heap
and managed by the GHC runtime, values pointed to by `SEXP`'s are
allocated on the R heap, managed by the R runtime. Therefore, the
lifetime of a SEXP value cannot extrude the lifetime of the R runtime
itself, just as any Haskell value becomes garbage once the GHC runtime
is terminated. That is, never invoke `hexp` on a value outside of the
dynamic scope of `withEmbeddedR`. This isn't a problem in practice,
because `withEmbeddedR` should be invoked only once, in the `main`
function of the program, just as the GHC runtime is initialized and
terminated only once, at the entry point of the binary (i.e., C's
`main()` function).

The second observation is that the `hexp` view function does pointer
dereferencing, which is a side-effect, *yet it claims to be a pure
function*. The pointer that is being dereferenced is the argument to
the function, of type `SEXP s a`. The reason dereferencing a pointer
is considered an effect is because its value depends on the state of
the global memory at the time when it occurs. This is because
a pointer identifies a memory location, called a *cell*, whose content
can be mutated.

Why then, does `hexp` claim to be pure? The reason is that `inline-r`
*assumes and encourages a restricted mode of use of R that rules out
mutation of the content of any cell*. In the absence of mutation,
dereferencing a pointer will always yield the same value, so no longer
needs to be classified as an effect. The restricted mode of use in
question bans any use of side-effects that break referential
transparency. So-called *benign* side-effects, extremely common in R,
do not compromise referential transparency and so are allowed.

Is such an assumption reasonable? After all, many R functions use
mutation and other side effects internally. However, it is also the
case that R uses *value semantics*, not *reference semantics*. That
is, including when passing arguments to functions, variables are
always bound to values, not to references to those values. Therefore,
given *e.g.* a global binding `x <- c(1, 2, 3)`, no call to any
function `f(x)` will alter the *value* of x, because all side-effects
of functions act on *copies* of `x` (the formal parameter of the
function doesn't share a reference). For example:

~~~ r
> x <- c(1,2,3)
> f <- function(y) y[1] <- 42
> f(x)
> x
[1] 1 2 3
~~~

Furthermore, in R, closures capture copies of their environment, so
that even the following preserves the value of `x`:

~~~ r
> x <- c(1,2,3)
> f <- function() x[1] <- 42
> f()
> x
[1] 1 2 3
~~~

The upshot is that due to its value semantics, R effectively limits
the scope of any mutation effects to the lexical scope of the
function. Therefore, any function whose only side-effect is mutation
is safe to call from a pure context.

Conversely, evaluating any `SEXP` in a pure context in Haskell is
*unsafe* in the presence of mutation of the global environment. For
example,

~~~ haskell
f :: SEXP s a -> (R s SomeSEXP,HExp a)
f x = let h = hexp x
         in ([r| x_hs <- 'hello' |], h)
~~~

The value of the expression `snd (f x)` depends on whether it is evaluated
before or after evaluating the monadic computation `fst (f x)`.

*Note:* `inline-r` merely encourages, but has of course no way of
*enforcing* a principled use of R that keeps to benign side-effects,
because owing to the dynamic typing of R code, there is no precise
static analysis that can detect bad side-effects.

### Physical and structural equality on R values

The standard library defines an `Eq` instance for `Ptr`, which simply
compares the addresses of the pointers. Because `SEXP s a` is a `Ptr`
in disguise, `s1 == s2` where `s1`, `s2` are `SEXP`s tests for
*physical equality*, namely whether `s1` and `s2` are one and the same
object.

Often this is not what we want. In fact most `Eq` instances in Haskell
test for *structural equality*, a broader notion of equality. Under
physical equality, `Char x /= Char y` even if `x == y`, whereas under
structural equality, `x == y` implies `Char x == Char y`.

However, we need a notion broader still. Equality on two values of
uniform type is too restrictive for `HExp`, which is a GADT. Consider
symbols, which can be viewed using the `Symbol` constructor:

~~~ haskell
Symbol :: SEXP s (R.Vector Word8)
       -> SEXP s a
       -> Maybe (SEXP s b)
       -> HExp R.Symbol
~~~

The second field in a symbol is its "value", which can be of any form,
*a priori* unknown. Therefore, when comparing two symbols recursively,
one cannot compare the two values at the same type. While type
refinement occurring *after* pattern matching on the values themselves
will always unify both types if the values are indeed equal, this is
not known to be the case *before* pattern matching. In any case, we
want to be also be able to compare values that are not in fact equal.
For this, we need a slightly generalized notion of equality, called
*heterogeneous equality*:

~~~ haskell
-- | Heterogeneous equality.
(===) :: TestEquality f => f a -> f b -> Bool
x === y = isJust $ testEquality x y
~~~

The `TestEquality` class
[comes from `base`](https://downloads.haskell.org/~ghc/latest/docs/html/libraries/base-4.8.1.0/Data-Type-Equality.html).
`(===)` is a generalization of `(==)` where the types of the arguments
can be indexed by arbitrary types.

If the type checker knows statically how to unify the types of two
values you want to compare, then `(==)` suffices. This is the case
most of the time. But if not, then you can use `(===)` to compare the
values.

The `Eq` instance for `HExp` is defined in terms of the `HEq`
instance. See `H.HExp` for its definition. It compares values for
structural equality.
