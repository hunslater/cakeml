open preamble;
open terminationTheory
open ml_translatorLib ml_translatorTheory;
open compiler64_preludeProgTheory;

val _ = new_theory "compiler64Prog"

(* temporary *)
val _ = translation_extends "compiler64_preludeProg";

val RW = REWRITE_RULE
val RW1 = ONCE_REWRITE_RULE
fun list_dest f tm =
  let val (x,y) = f tm in list_dest f x @ list_dest f y end
  handle HOL_ERR _ => [tm];
val dest_fun_type = dom_rng
val mk_fun_type = curry op -->;
fun list_mk_fun_type [ty] = ty
  | list_mk_fun_type (ty1::tys) =
      mk_fun_type ty1 (list_mk_fun_type tys)
  | list_mk_fun_type _ = fail()

val _ = add_preferred_thy "-";
val _ = add_preferred_thy "termination";

val NOT_NIL_AND_LEMMA = prove(
  ``(b <> [] /\ x) = if b = [] then F else x``,
  Cases_on `b` THEN FULL_SIMP_TAC std_ss []);

val extra_preprocessing = ref [MEMBER_INTRO,MAP];

val matches = ref ([]: term list);

fun def_of_const tm = let
  val res = dest_thy_const tm handle HOL_ERR _ =>
              failwith ("Unable to translate: " ^ term_to_string tm)
  val name = (#Name res)
  fun def_from_thy thy name =
    DB.fetch thy (name ^ "_def") handle HOL_ERR _ =>
    DB.fetch thy (name ^ "_DEF") handle HOL_ERR _ =>
    DB.fetch thy (name ^ "_thm") handle HOL_ERR _ =>
    DB.fetch thy name
  val def = def_from_thy "termination" name handle HOL_ERR _ =>
            def_from_thy (#Thy res) name handle HOL_ERR _ =>
            failwith ("Unable to find definition of " ^ name)

  val insts = if exists (fn term => can (find_term (can (match_term term))) (concl def)) (!matches) then [alpha |-> ``:64``,beta|->``:64``] else []

  val def = def |> INST_TYPE insts
                |> CONV_RULE (DEPTH_CONV BETA_CONV)
                (* TODO: This ss messes up defs containing if-then-else
                with constant branches
                |> SIMP_RULE bool_ss [IN_INSERT,NOT_IN_EMPTY]*)
                |> REWRITE_RULE [NOT_NIL_AND_LEMMA]
  in def end

val _ = (find_def_for_const := def_of_const);

val _ = use_long_names:=true;

val spec64 = INST_TYPE[alpha|->``:64``]

val conv64 = GEN_ALL o CONV_RULE (wordsLib.WORD_CONV) o spec64 o SPEC_ALL

val conv64_RHS = GEN_ALL o CONV_RULE (RHS_CONV wordsLib.WORD_CONV) o spec64 o SPEC_ALL

(*
When word_to_word$compile is done:

val _ = translate (compile_def |> SIMP_RULE std_ss [stubs_def] |> conv64_RHS)
*)

open word_simpTheory word_allocTheory word_instTheory

val _ = matches:= [``foo:'a wordLang$prog``,``foo:'a wordLang$exp``,``foo:'a word``,``foo: 'a reg_imm``,``foo:'a arith``,``foo: 'a addr``]

val _ = translate (spec64 compile_exp_def)

val _ = translate (spec64 max_var_def)

(* TODO: Remove from x64Prog *)
val _ = translate (conv64_RHS integer_wordTheory.w2i_eq_w2n)
val _ = translate (conv64_RHS integer_wordTheory.WORD_LEi)

val _ = translate (wordLangTheory.num_exp_def |> conv64)
val _ = translate (inst_select_exp_def |> conv64 |> SIMP_RULE std_ss [word_mul_def,word_2comp_def] |> conv64)

val _ = translate (op_consts_def|>conv64|> SIMP_RULE std_ss [word_2comp_def] |> conv64)

val rws = prove(``
  ($+ = λx y. x + y) ∧
  ($&& = λx y. x && y) ∧
  ($|| = λx y. x || y) ∧
  ($?? = λx y. x ?? y)``,
  fs[FUN_EQ_THM])

val _ = translate (wordLangTheory.word_op_def |> ONCE_REWRITE_RULE [rws]|> conv64 |> SIMP_RULE std_ss [word_mul_def,word_2comp_def] |> conv64)

val _ = translate (convert_sub_def |> conv64 |> SIMP_RULE std_ss [word_2comp_def,word_mul_def] |> conv64)

val _ = translate (spec64 pull_exp_def)

val word_inst_pull_exp_side = prove(``
  ∀x. word_inst_pull_exp_side x ⇔ T``,
  ho_match_mp_tac pull_exp_ind>>rw[]>>
  simp[Once (fetch "-" "word_inst_pull_exp_side_def"),
      fetch "-" "word_inst_optimize_consts_side_def",
      wordLangTheory.word_op_def]>>
  metis_tac[]) |> update_precondition

val _ = translate (spec64 inst_select_def)

(* Argh, SSA has a few defs that have both beta AND alpha although only the alpha is necessary *)
val _ = translate (spec64 list_next_var_rename_move_def)

val word_alloc_list_next_var_rename_move_side = prove(``
  ∀x y z. word_alloc_list_next_var_rename_move_side x y z ⇔ T``,
  simp[fetch "-" "word_alloc_list_next_var_rename_move_side_def"]>>
  Induct_on`z`>>fs[list_next_var_rename_def]>>rw[]>>
  rpt(pairarg_tac>>fs[])>>
  res_tac>>rpt var_eq_tac>>fs[]) |> update_precondition

val _ = translate (spec64 full_ssa_cc_trans_def)

val word_alloc_full_ssa_cc_trans_side = prove(``
  ∀x y. word_alloc_full_ssa_cc_trans_side x y``,
  simp[fetch "-" "word_alloc_full_ssa_cc_trans_side_def"]>>
  rw[]>>pop_assum kall_tac>>
  map_every qid_spec_tac [`v6`,`v7`,`y`]>>
  ho_match_mp_tac ssa_cc_trans_ind>>
  rw[]>>
  simp[Once (fetch "-" "word_alloc_ssa_cc_trans_side_def")]>>
  map_every qid_spec_tac [`ssa`,`na`]>>
  Induct_on`ls`>>fs[list_next_var_rename_def]>>rw[]>>
  rpt(pairarg_tac>>fs[])>>
  res_tac>>rpt var_eq_tac>>fs[]) |> update_precondition

(* TODO: this fails, I think because the exp induction is messed up...

val _ = translate (spec64 get_live_exp_def)

val _ = translate (spec64 remove_dead_def|> SIMP_RULE std_ss [get_live_def])
*)

val _ = translate (spec64 three_to_two_reg_def)

(* TODO: move the allocator translation, then translate word_alloc *)

val _ = export_theory();