import Foundation
import Supabase

enum SupabaseManager {
    static let client = SupabaseClient(
        supabaseURL: URL(string: "https://qobxrxljvadihscouoay.supabase.co")!,
        supabaseKey: "sb_publishable_DpAd3wTGdfQDIcyk2FpLGA_zLshHtcp"
    )
}
