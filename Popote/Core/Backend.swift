import Foundation
import Supabase

/// Connection details for the website's Supabase project and server functions.
/// The publishable key is the same public key the website ships in its JavaScript.
enum Backend {
    static let supabaseURL = URL(string: "https://pwlrzjmqagwlvncfvfel.supabase.co")!
    static let publishableKey = "sb_publishable_9ixRQH2cuoWUzbKG3mj4YQ_T_J0zG_T"
    static let webURL = URL(string: "https://la-popote-de-tata-suzanne.lovable.app")!
    static let photoBucket = "recipe-photos"

    static let client: SupabaseClient = SupabaseClient(
        supabaseURL: supabaseURL,
        supabaseKey: publishableKey,
        options: SupabaseClientOptions(
            auth: .init(
                storage: KeychainLocalStorage(service: "net.dauernheim.popote.auth"),
                emitLocalSessionAsInitialSession: true
            )
        )
    )
}
