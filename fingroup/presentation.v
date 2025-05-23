(* (c) Copyright 2006-2016 Microsoft Corporation and Inria.                  *)
(* Distributed under the terms of CeCILL-B.                                  *)
From mathcomp Require Import ssreflect ssrbool ssrfun eqtype ssrnat seq.
From mathcomp Require Import fintype finset fingroup morphism.

(******************************************************************************)
(* Support for generator-and-relation presentations of groups. We provide the *)
(* syntax:                                                                    *)
(*  G \homg Grp (x_1 : ... x_n : s_1 = t_1, ..., s_m = t_m)                   *)
(*    <=> G is generated by elements x_1, ..., x_m satisfying the relations   *)
(*        s_1 = t_1, ..., s_m = t_m, i.e., G is a homomorphic image of the    *)
(*        group generated by the x_i, subject to the relations s_j = t_j.     *)
(*  G \isog Grp (x_1 : ... x_n : s_1 = t_1, ..., s_m = t_m)                   *)
(*    <=> G is isomorphic to the largest finite factor of the group generated *)
(*        by the x_i, subject to the relations s_j = t_j. In particular,      *)
(*        if the abstract group defined by the presentation is finite,        *)
(*        it means that G is actually isomorphic to it. This is an            *)
(*        intensional predicate (in Prop), as even the non-triviality of a    *)
(*        generated group is undecidable.                                     *)
(* Syntax details:                                                            *)
(*  - Grp is a literal constant.                                              *)
(*  - There must be at least one generator and one relation.                  *)
(*  - A relation s_j = 1 can be abbreviated as simply s_j (a.k.a. a relator). *)
(*  - Two consecutive relations s_j = t, s_j+1 = t can be abbreviated         *)
(*    s_j = s_j+1 = t.                                                        *)
(*  - The s_j and t_j are terms built from the x_i and the standard group     *)
(*    operators *, 1, ^-1, ^+, ^-, ^, [~ u_1, ..., u_k]; no other operator or *)
(*    abbreviation may be used, as the notation is implemented using static   *)
(*    overloading.                                                            *)
(*  - This is the closest we could get to the notation used in Aschbacher,    *)
(*       Grp (x_1, ... x_n : t_1,1 = ... = t_1,k1, ..., t_m,1 = ... = t_m,km) *)
(*    under the current limitations of the Coq Notation facility.             *)
(* Semantics details:                                                         *)
(* - G \isog Grp (...) : Prop expands to the statement                        *)
(*      forall rT (H : {group rT}), (H \homg G) = (H \homg Grp (...))         *)
(*   (with rT : finGroupType).                                                *)
(* - G \homg Grp (x_1 : ... x_n : s_1 = t_1, ..., s_m = t_m) : bool, with     *)
(*   G : {set gT}, is convertible to the boolean expression                   *)
(*     [exists t : gT * ... gT, let: (x_1, ..., x_n) := t in                  *)
(*       (<[x_1]> <*> ... <*> <[x_n]>, (s_1, ... (s_m-1, s_m) ...))           *)
(*          == (G, (t_1, ... (t_m-1, t_m) ...))]                              *)
(*   where the tuple comparison above is convertible to the conjunction       *)
(*       [&& <[x_1]> <*> ... <*> <[x_n]> == G, s_1 == t_1, ... & s_m == t_m]  *)
(*   Thus G \homg Grp (...) can be easily exploited by destructing the tuple  *)
(*   created case/existsP, then destructing the tuple equality with case/eqP. *)
(*   Conversely it can be proved by using apply/existsP, providing the tuple  *)
(*   with a single exists (u_1, ..., u_n), then using rewrite !xpair_eqE /=   *)
(*   to expose the conjunction, and optionally using an apply/and{m+1}P view  *)
(*   to split it into subgoals (in that case, the rewrite is in principle     *)
(*   redundant, but necessary in practice because of the poor performance of  *)
(*   conversion in the Coq unifier).                                          *)
(******************************************************************************)

Set Implicit Arguments.
Unset Strict Implicit.
Unset Printing Implicit Defensive.

Import GroupScope.

Module Presentation.

Section Presentation.

Implicit Types gT rT : finGroupType.
Implicit Type vT : finType. (* tuple value type *)

Inductive term :=
  | Cst of nat
  | Idx
  | Inv of term
  | Exp of term & nat
  | Mul of term & term
  | Conj of term & term
  | Comm of term & term.

Fixpoint eval {gT} e t : gT :=
  match t with
  | Cst i => nth 1 e i
  | Idx => 1
  | Inv t1 => (eval e t1)^-1
  | Exp t1 n => eval e t1 ^+ n
  | Mul t1 t2 => eval e t1 * eval e t2
  | Conj t1 t2 => eval e t1 ^ eval e t2
  | Comm t1 t2 => [~ eval e t1, eval e t2]
  end.

Inductive formula := Eq2 of term & term | And of formula & formula.
Definition Eq1 s := Eq2 s Idx.
Definition Eq3 s1 s2 t := And (Eq2 s1 t) (Eq2 s2 t).

Inductive rel_type := NoRel | Rel vT of vT & vT.

Definition bool_of_rel r := if r is Rel vT v1 v2 then v1 == v2 else true.
Local Coercion bool_of_rel : rel_type >-> bool.

Definition and_rel vT (v1 v2 : vT) r :=
  if r is Rel wT w1 w2 then Rel (v1, w1) (v2, w2) else Rel v1 v2.
 
Fixpoint rel {gT} (e : seq gT) f r :=
  match f with
  | Eq2 s t => and_rel (eval e s) (eval e t) r
  | And f1 f2 => rel e f1 (rel e f2 r)
  end.

Inductive type := Generator of term -> type | Formula of formula.
Definition Cast p : type := p. (* syntactic scope cast *)
Local Coercion Formula : formula >-> type.

Inductive env gT := Env of {set gT} & seq gT.
Definition env1 {gT} (x : gT : finType) := Env <[x]> [:: x].

Fixpoint sat gT vT B n (s : vT -> env gT) p :=
  match p with
  | Formula f =>
    [exists v, let: Env A e := s v in and_rel A B (rel (rev e) f NoRel)]
  | Generator p' =>
    let s' v := let: Env A e := s v.1 in Env (A <*> <[v.2]>) (v.2 :: e) in
    sat B n.+1 s' (p' (Cst n))
  end.

Definition hom gT (B : {set gT}) p := sat B 1 env1 (p (Cst 0)).
Definition iso gT (B : {set gT}) p :=
  forall rT (H : {group rT}), (H \homg B) = hom H p.

End Presentation.

End Presentation.

Import Presentation.

Coercion bool_of_rel : rel_type >-> bool.
Coercion Eq1 : term >-> formula.
Coercion Formula : formula >-> type.

Declare Custom Entry group_presentation.

Notation "x * y" := (Mul x y)
  (in custom group_presentation at level 40, left associativity).
Notation "x ^+ n" := (Exp x n)
  (in custom group_presentation at level 29, n constr at level 28).
Notation "x ^ y" := (Conj x y)
  (in custom group_presentation at level 30, right associativity).
Notation "x ^-1" := (Inv x) (in custom group_presentation at level 3).
Notation "x ^- n" := (Inv (Exp x n))
  (in custom group_presentation at level 29, n constr at level 28).
Notation "[ ~ x1 , x2 , .. , xn ]" := (Comm .. (Comm x1 x2) .. xn)
  (in custom group_presentation, x1, x2, xn at level 100).
Notation "x = y" := (Eq2 x y) (in custom group_presentation at level 70).
Notation "x = y = z" := (Eq3 x y z) (in custom group_presentation at level 70,
  y at next level).
Notation "r1 , r2 , .. , rn" := (And .. (And r1 r2) .. rn)
  (in custom group_presentation at level 200).
Notation "( p )" := p (in custom group_presentation, p at level 200).
Notation "1" := Idx (in custom group_presentation).
Notation "x" := x (in custom group_presentation at level 0, x ident).

Notation "x : p" := (Generator (fun x => Cast p))
  (in custom group_presentation, x ident, p custom group_presentation at level 200).

Arguments hom _ _%_group_scope.
Arguments iso _ _%_group_scope.

Notation "H \homg 'Grp' p" := (hom H p)
  (at level 70, p at level 0, format "H  \homg  'Grp'  p") : group_scope.

Notation "H \isog 'Grp' p" := (iso H p)
  (at level 70, p at level 0, format "H  \isog  'Grp'  p") : group_scope.

Notation "H \homg 'Grp' ( x : p )" := (hom H (fun x => Cast p))
  (at level 70, x ident, p custom group_presentation at level 200,
   format "'[hv' H '/ '  \homg  'Grp'  ( x  :  p ) ']'") : group_scope.

Notation "H \isog 'Grp' ( x : p )" := (iso H (fun x => Cast p))
  (at level 70, x ident, p custom group_presentation at level 200,
   format "'[hv' H '/ '  \isog  'Grp'  ( x  :  p ) ']'") : group_scope.

Section PresentationTheory.

Implicit Types gT rT : finGroupType.

Import Presentation.

Lemma isoGrp_hom gT (G : {group gT}) p : G \isog Grp p -> G \homg Grp p.
Proof. by move <-; apply: homg_refl. Qed.

Lemma isoGrpP gT (G : {group gT}) p rT (H : {group rT}) :
  G \isog Grp p -> reflect (#|H| = #|G| /\ H \homg Grp p) (H \isog G).
Proof.
move=> isoGp; apply: (iffP idP) => [isoGH | [oH homHp]].
  by rewrite (card_isog isoGH) -isoGp isog_hom.
by rewrite isogEcard isoGp homHp /= oH.
Qed.

Lemma homGrp_trans rT gT (H : {set rT}) (G : {group gT}) p :
  H \homg G -> G \homg Grp p -> H \homg Grp p.
Proof.
case/homgP=> h <-{H}; rewrite /hom; move: {p}(p _) => p.
have evalG e t: all [in G] e -> eval (map h e) t = h (eval e t).
  move=> Ge; apply: (@proj2 (eval e t \in G)); elim: t => /=.
  - move=> i; case: (leqP (size e) i) => [le_e_i | lt_i_e].
      by rewrite !nth_default ?size_map ?morph1.
    by rewrite (nth_map 1) // [_ \in G](allP Ge) ?mem_nth.
  - by rewrite morph1.
  - by move=> t [Gt ->]; rewrite groupV morphV.
  - by move=> t [Gt ->] n; rewrite groupX ?morphX.
  - by move=> t1 [Gt1 ->] t2 [Gt2 ->]; rewrite groupM ?morphM.
  - by move=> t1 [Gt1 ->] t2 [Gt2 ->]; rewrite groupJ ?morphJ.
  by move=> t1 [Gt1 ->] t2 [Gt2 ->]; rewrite groupR ?morphR.
have and_relE xT x1 x2 r: @and_rel xT x1 x2 r = (x1 == x2) && r :> bool.
  by case: r => //=; rewrite andbT.
have rsatG e f: all [in G] e -> rel e f NoRel -> rel (map h e) f NoRel.
  move=> Ge; have: NoRel -> NoRel by []; move: NoRel {2 4}NoRel.
  elim: f => [x1 x2 | f1 IH1 f2 IH2] r hr IHr; last by apply: IH1; apply: IH2.
  by rewrite !and_relE !evalG //; case/andP; move/eqP->; rewrite eqxx.
set s := env1; set vT := gT : finType in s *.
set s' := env1; set vT' := rT : finType in s' *.
have (v): let: Env A e := s v in
  A \subset G -> all [in G] e /\ exists v', s' v' = Env (h @* A) (map h e).
- rewrite /= cycle_subG andbT => Gv; rewrite morphim_cycle //.
  by split; last exists (h v).
elim: p 1%N vT vT' s s' => /= [p IHp | f] n vT vT' s s' Gs.
  apply: IHp => [[v x]] /=; case: (s v) {Gs}(Gs v) => A e /= Gs.
  rewrite join_subG cycle_subG; case/andP=> sAG Gx; rewrite Gx.
  have [//|-> [v' def_v']] := Gs; split=> //; exists (v', h x); rewrite def_v'.
  by congr (Env _ _); rewrite morphimY ?cycle_subG // morphim_cycle.
case/existsP=> v; case: (s v) {Gs}(Gs v) => /= A e Gs.
rewrite and_relE => /andP[/eqP defA rel_f].
have{Gs} [|Ge [v' def_v']] := Gs; first by rewrite defA.
apply/existsP; exists v'; rewrite def_v' and_relE defA eqxx /=.
by rewrite -map_rev rsatG ?(eq_all_r (mem_rev e)).
Qed.

Lemma eq_homGrp gT rT (G : {group gT}) (H : {group rT}) p :
  G \isog H -> (G \homg Grp p) = (H \homg Grp p).
Proof.
by rewrite isogEhom => /andP[homGH homHG]; apply/idP/idP; apply: homGrp_trans.
Qed.

Lemma isoGrp_trans gT rT (G : {group gT}) (H : {group rT}) p :
  G \isog H -> H \isog Grp p -> G \isog Grp p.
Proof. by move=> isoGH isoHp kT K; rewrite -isoHp; apply: eq_homgr. Qed.

Lemma intro_isoGrp gT (G : {group gT}) p :
    G \homg Grp p -> (forall rT (H : {group rT}), H \homg Grp p -> H \homg G) ->
  G \isog Grp p.
Proof.
move=> homGp freeG rT H.
by apply/idP/idP=> [homHp|]; [apply: homGrp_trans homGp | apply: freeG].
Qed.

End PresentationTheory.

