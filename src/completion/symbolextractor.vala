using LanguageServer;

/**
 * A backwards parser that makes extraordinary attempts to find the current
 * symbol at the cursor when all other methods have failed.
 */
class Vls.SymbolExtractor : Object {
    private long idx;
    private Position pos;
    private Vala.Scope scope;
    private Vala.SourceFile source_file;
    private Vala.CodeContext context;

    private bool attempted_extract;
    private Vala.Symbol? _extracted_symbol;
    public Vala.Symbol? extracted_symbol {
        get {
            if (_extracted_symbol == null && !attempted_extract)
                compute_extracted_symbol ();
            return _extracted_symbol;
        }
    }

    public SymbolExtractor (Position pos, Vala.Scope scope, Vala.SourceFile source_file, Vala.CodeContext? context = null) {
        this.idx = (long) Util.get_string_pos (source_file.content, pos.line - 1, pos.character);
        this.pos = pos;
        this.scope = scope;
        this.source_file = source_file;
        if (context != null)
            this.context = context;
        else {
            assert (Vala.CodeContext.get () == source_file.context);
            this.context = source_file.context;
        }
    }

    private void compute_extracted_symbol () {
        var queue = new Queue<string> ();

        skip_whitespace ();
        for (string? ident = null; (ident = parse_ident ()) != null; ) {
            queue.push_head (ident);
            skip_whitespace ();
            if (!expect_char ('.'))
                break;
        }

        attempted_extract = true;

        // perform lookup
        if (queue.length == 0)
            return;

        // 1. find symbol coresponding to first component
        // 2. with the first symbol found, generate member accesses
        //    for additional components
        // 3. resolve the member accesses, and get the symbol_reference

        string first_part = queue.pop_head ();
        Vala.Scope? current_scope = scope;
        Vala.Symbol? head_sym = null;
        while (current_scope != null && head_sym == null)
            head_sym = current_scope.lookup (first_part);

        if (head_sym == null) {
            debug ("failed to find symbol for head symbol %s", first_part);
            return;
        }

        var ma = new Vala.MemberAccess (null, first_part);
        ma.symbol_reference = head_sym;

        while (!queue.is_empty ())
            ma = new Vala.MemberAccess (ma, queue.pop_head ());

        ma.check (this.context);
        _extracted_symbol = ma.symbol_reference;
    }

    //    private bool expect_string (string s) {
    //        if (source_file.content[idx+1 - s.length : idx+1] == s)
    //            if (idx >= s.length) {
    //                idx -= s.length;
    //                return true;
    //            }
    //        return false;
    //    }

    private bool expect_char (char c) {
        if (source_file.content[idx] == c) {
            if (idx > 0)
                idx--;
            return true;
        }
        return false;
    }

    private void skip_whitespace () {
        while (idx > 0 && source_file.content[idx].isspace ())
            idx--;
    }

    private string? parse_ident () {
        long lb_idx = idx;

        while (lb_idx > 0 && (source_file.content[lb_idx].isalnum () || source_file.content[lb_idx] == '_'))
            lb_idx--;

        if (!(source_file.content[lb_idx].isalnum () || source_file.content[lb_idx] == '_') && lb_idx < idx)
            lb_idx++;

        string ident = source_file.content.substring (lb_idx, idx - lb_idx);
        idx = lb_idx;   // update idx

        return ident.length == 0 ? null : ident;
    }
}
