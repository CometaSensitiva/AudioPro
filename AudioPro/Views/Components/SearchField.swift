import SwiftUI

/// Campo di ricerca condiviso del livello controllo: capsula **glass**
/// interattiva (non material fatto a mano). Un'unica implementazione per la
/// ricerca coda file (toolbar Esportazione) e la ricerca trascrizione
/// (in-content Riproduzione), così raggi, padding e affordance restano
/// identici.
struct SearchField: View {
    let placeholder: String
    @Binding var text: String

    /// Larghezza fissa del campo (toolbar). `nil` = si espande al contenitore.
    var fieldWidth: CGFloat? = nil
    /// Etichetta contatore match (es. "2 di 7"), mostrata solo con testo.
    var matchCounter: String? = nil
    /// Azioni di navigazione fra i match (ricerca trascrizione).
    var onPrevious: (() -> Void)? = nil
    var onNext: (() -> Void)? = nil
    var isNavigationDisabled: Bool = false
    /// Invio in tastiera: di norma "match successivo".
    var onSubmit: (() -> Void)? = nil
    /// Esc / pulsante chiudi. Se presente mostra la ✕ di chiusura al posto
    /// del semplice "cancella testo".
    var onClose: (() -> Void)? = nil
    /// Prende il focus alla comparsa (find bar).
    var focusesOnAppear: Bool = false
    /// Cambiare questo token richiede esplicitamente il focus, anche quando la
    /// find bar è già visibile e quindi non riceve un nuovo `onAppear`.
    var focusRequest: UUID? = nil

    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(width: fieldWidth)
                .onSubmit { onSubmit?() }
                .accessibilityLabel(placeholder)

            if let matchCounter, text.isEmpty == false {
                Text(matchCounter)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .accessibilityLabel("Risultati della ricerca")
                    .accessibilityValue(matchCounter)
            }

            if let onPrevious {
                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(isNavigationDisabled)
                .help("Risultato precedente")
                .accessibilityLabel("Risultato precedente")
            }

            if let onNext {
                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(isNavigationDisabled)
                .help("Risultato successivo (⏎)")
                .accessibilityLabel("Risultato successivo")
            }

            if let onClose {
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Chiudi ricerca (Esc)")
                .accessibilityLabel("Chiudi ricerca")
            } else if text.isEmpty == false {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Cancella ricerca")
                .accessibilityLabel("Cancella ricerca")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .onExitCommand { onClose?() }
        .onAppear {
            if focusesOnAppear { isFocused = true }
        }
        .onChange(of: focusRequest) { _, request in
            if request != nil { isFocused = true }
        }
    }
}

struct SearchField_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            SearchField(placeholder: "Cerca nella coda file", text: .constant(""), fieldWidth: 220)
            SearchField(
                placeholder: "Cerca nella trascrizione",
                text: .constant("logistica"),
                matchCounter: "2 di 7",
                onPrevious: {},
                onNext: {},
                onClose: {}
            )
        }
        .padding()
        .frame(width: 460)
    }
}
