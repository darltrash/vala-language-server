/* codelensengine.vala
 *
 * Copyright 2021 Princeton Ferro <princetonferro@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation, either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

using Gee;
using Lsp;

enum Vls.Command {
    /**
     * The editor should display the base symbol of a method or property.
     */
    EDITOR_SHOW_BASE_SYMBOL,

    /**
     * The editor should display the symbol hidden by the current symbol.
     */
    EDITOR_SHOW_HIDDEN_SYMBOL;

    public unowned string to_string () {
        switch (this) {
            case EDITOR_SHOW_BASE_SYMBOL:
                return "vala.showBaseSymbol";
            case EDITOR_SHOW_HIDDEN_SYMBOL:
                return "vala.showHiddenSymbol";
        }
        assert_not_reached ();
    }
}

namespace Vls.CodeLensEngine {
    /**
     * Represent the symbol in a special way for code lenses:
     * `{parent with type parameters}.{symbol_name}`
     * 
     * We don't care to show modifiers, return types, and/or parameters.
     */
    string represent_symbol (Vala.Symbol current_symbol, Vala.Symbol target_symbol) {
        var builder = new StringBuilder ();

        if (current_symbol.parent_symbol is Vala.TypeSymbol) {
            Vala.DataType? target_symbol_parent_type = null;
            var ancestor_types = new GLib.Queue<Vala.DataType> ();
            ancestor_types.push_tail (Vala.SemanticAnalyzer.get_data_type_for_symbol (current_symbol.parent_symbol));

            while (target_symbol_parent_type == null && !ancestor_types.is_empty ()) {
                var parent_type = ancestor_types.pop_head ();
                if (parent_type.type_symbol is Vala.Class) {
                    foreach (var base_type in ((Vala.Class)parent_type.type_symbol).get_base_types ()) {
                        var actual_base_type = base_type.get_actual_type (parent_type, null, null);
                        if (base_type.type_symbol == target_symbol.parent_symbol) {
                            target_symbol_parent_type = actual_base_type;
                            break;
                        }
                        ancestor_types.push_tail (actual_base_type);
                    }
                } else if (parent_type.type_symbol is Vala.Interface) {
                    foreach (var base_type in ((Vala.Interface)parent_type.type_symbol).get_prerequisites ()) {
                        var actual_base_type = base_type.get_actual_type (parent_type, null, null);
                        if (base_type.type_symbol == target_symbol.parent_symbol) {
                            target_symbol_parent_type = actual_base_type;
                            break;
                        }
                        ancestor_types.push_tail (actual_base_type);
                    }
                } else if (parent_type.type_symbol is Vala.Struct) {
                    var base_type = ((Vala.Struct)parent_type.type_symbol).base_type;
                    var actual_base_type = base_type.get_actual_type (parent_type, null, null);
                    if (base_type.type_symbol == target_symbol.parent_symbol) {
                        target_symbol_parent_type = actual_base_type;
                        break;
                    }
                    ancestor_types.push_tail (actual_base_type);
                }
            }

            builder.append (CodeHelp.get_symbol_representation (
                    target_symbol_parent_type,
                    target_symbol.parent_symbol,
                    current_symbol.scope,
                    true,
                    null,
                    null,
                    false,
                    true));

            builder.append_c ('.');
        }

        builder.append (target_symbol.name);
        if (target_symbol is Vala.Callable)
            builder.append ("()");
        return builder.str;
    }

    Array<Variant> create_arguments (Vala.Symbol current_symbol, Vala.Symbol target_symbol) {
        var arguments = new Array<Variant> ();

        try {
            arguments.append_val (Util.object_to_variant (new Location.from_sourceref (current_symbol.source_reference)));
            arguments.append_val (Util.object_to_variant (new Location.from_sourceref (target_symbol.source_reference)));
        } catch (Error e) {
            warning ("failed to create arguments for command: %s", e.message);
        }

        return arguments;
    }
}
