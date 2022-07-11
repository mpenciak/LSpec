/-
Copyright (c) 2022 Henrik Böving. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Henrik Böving
-/
import LSpec.Control.DefaultRange

/-!
# Rand Monad and Random Class

This module provides tools for formulating computations guided by randomness and for
defining objects that can be created randomly.

## Main definitions
  * `Rand` and `RandT` monad for computations guided by randomness;
  * `Random` class for objects that can be generated randomly;
    * `random` to generate one object;
  * `BoundedRandom` class for objects that can be generated randomly inside a range;
    * `randomR` to generate one object inside a range;
  * `IO.runRand` to run a randomized computation inside the `IO` monad;

## Notes
  * Often we need to do some panic-possible things like use `List.get!`.
    In these cases, panic often needs an instance of `Inhabited (Gen α)`;
    the default generator will always be `StdGen` with `seed := 0`.

## References
  * Similar library in Haskell: https://hackage.haskell.org/package/MonadRandom
-/

/-- A monad to generate random objects using the generic generator type `g` -/
abbrev RandT (g : Type) := StateM (ULift g)

instance inhabitedRandT [Inhabited g] [Inhabited α] : Inhabited (RandT g α) where 
  default := fun _ => pure (default, .up default)

/-- A monad to generate random objects using the generator type `Rng` -/
abbrev Rand (α : Type u) := RandT StdGen α

instance inhabitedStdGen : Inhabited StdGen where 
  default := mkStdGen

/-- `Random α` gives us machinery to generate values of type `α` -/
class Random (α : Type u) where
  randomR [RandomGen g] (lo hi : α) : RandT g α

-- /-- `BoundedRandom α` gives us machinery to generate values of type `α` between certain bounds -/
-- class BoundedRandom (α : Type u) [LE α] where
--   randomR {g : Type} (lo hi : α) (h : lo ≤ hi) [RandomGen g] : RandT g {a // lo ≤ a ∧ a ≤ hi}

namespace Rand
  /-- Generate one more `Nat` -/
  def next [RandomGen g] : RandT g Nat := do
    let rng := (← get).down
    let (res, new) := RandomGen.next rng
    set (ULift.up new)
    pure res

  /-- Create a new random number generator distinct from the one stored in the state -/
  def split {g : Type} [RandomGen g] : RandT g g := do
    let rng := (← get).down
    let (r1, r2) := RandomGen.split rng
    set (ULift.up r1)
    pure r2

  /-- Get the range of Nat that can be generated by the generator `g` -/
  def range {g : Type} [RandomGen g] : RandT g (Nat × Nat) := do
    let rng := (← get).down
    pure <| RandomGen.range rng
end Rand

namespace Random

open Rand

/-- Generate a random value of type `α`. -/
def rand (α : Type u) [Random α] [range : DefaultRange α] [RandomGen g] : RandT g α := 
  Random.randomR range.lo range.hi

/-- Generate a random value of type `α` between `x` and `y` inclusive. -/
def randBound (α : Type u) [Random α] (lo hi : α) [RandomGen g] : RandT g α :=
  Random.randomR lo hi

def randFin {n : Nat} [RandomGen g] : RandT g (Fin n.succ) :=
  λ ⟨g⟩ => randNat g 0 n.succ |>.map Fin.ofNat ULift.up

instance : Random Bool where
  randomR := fun lo hi g => 
    let (n, g') := RandomGen.next g.down
    match lo, hi with
    | true, false => (n % 2 == 1, .up g') 
    | false, true => (n % 2 == 0, .up g') -- this doesn't matter btw, I'm just being quirky
    | x, _ => (x, .up g')

instance : Random Nat where
  randomR := fun lo hi g => 
    let (n, g') := randNat g.down lo hi 
    (n, .up g')

instance {n : Nat} : Random (Fin n.succ) where
  randomR := fun lo hi g => 
    let (n, g') := randNat g.down lo hi  
    (.ofNat n, .up g')

instance : Random Int where
  randomR := fun lo hi g => 
    let lo' := if lo > hi then hi else lo
    let hi' := if lo > hi then lo else hi
    let hi'' := (hi' - lo').toNat
    let (n, g') := randNat g.down 0 hi''
    (.ofNat n - lo', .up g')

end Random

/-- Computes a `Rand α` using the global `stdGenRef` as RNG.
    Note that:
    - `stdGenRef` is not necessarily properly seeded on program startup
      as of now and will therefore be deterministic.
    - `stdGenRef` is not thread local, hence two threads accessing it
      at the same time will get the exact same generator.
-/
def IO.runRand (cmd : Rand α) : BaseIO α := do
  let stdGen ←  stdGenRef.get
  let rng := ULift.up stdGen
  let (res, new) := Id.run <| StateT.run cmd rng
  stdGenRef.set new.down
  pure res

def IO.runRandWith (seed : Nat) (cmd : Rand α) : BaseIO α := do
  pure $ (cmd.run (ULift.up $ mkStdGen seed)).1