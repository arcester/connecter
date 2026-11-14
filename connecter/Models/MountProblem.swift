import Foundation

/// The probable cause of a failed mount: a few words for the share's status
/// tag and a sentence for its tooltip. Derived from the same error the
/// activity log records.
enum MountProblem: Equatable {
    case wrongCredentials
    case missingPassword
    case shareNotFound
    case smbRefused
    case accountRestricted
    case unsupportedAuthentication
    case noAnswer
    case invalidAddress
    /// No known cause: the error's own (English) message.
    case other(String)

    init(_ error: Error) {
        switch error {
        case MountError.missingPassword:
            self = .missingPassword
        case MountError.mountTimedOut:
            self = .noAnswer
        case MountError.invalidURL:
            self = .invalidAddress
        case let MountError.mountFailed(message, status):
            switch status {
            case EACCES, EPERM, EAUTH, ENEEDAUTH: self = .wrongCredentials
            case ENOENT, -5998:                   self = .shareNotFound      // -5998: ENETFSNOSHARESAVAIL
            case ECONNREFUSED:                    self = .smbRefused
            case -5999:                           self = .accountRestricted  // ENETFSACCOUNTRESTRICTED
            case -5997:                           self = .unsupportedAuthentication // ENETFSNOAUTHMECHSUPP
            default:                              self = .other(message)
            }
        default:
            self = .other(error.localizedDescription)
        }
    }

    var title: String {
        switch self {
        case .wrongCredentials:          String(localized: "Wrong user or password")
        case .missingPassword:           String(localized: "No password")
        case .shareNotFound:             String(localized: "Share not found")
        case .smbRefused:                String(localized: "SMB refused")
        case .accountRestricted:         String(localized: "Account restricted")
        case .unsupportedAuthentication: String(localized: "Sign-in not supported")
        case .noAnswer:                  String(localized: "No answer")
        case .invalidAddress:            String(localized: "Invalid address")
        case .other:                     String(localized: "Error")
        }
    }

    var advice: String {
        switch self {
        case .wrongCredentials:
            String(localized: "The server rejected the user or the password. Correct them in the share, or in Server Settings… if it uses the server’s credentials.")
        case .missingPassword:
            String(localized: "There is no saved password for this user, and macOS does not answer without one. Enter it in the share or in Server Settings…")
        case .shareNotFound:
            String(localized: "The server has no share with this name, or this user cannot see it. Check the share’s path.")
        case .smbRefused:
            String(localized: "The server refuses SMB connections. Check that file sharing over SMB is turned on.")
        case .accountRestricted:
            String(localized: "The server says the account is locked or not allowed to connect.")
        case .unsupportedAuthentication:
            String(localized: "The server and macOS have no sign-in method in common. Turn on SMB 2 or 3 and NTLMv2 on the server.")
        case .noAnswer:
            String(localized: "The server answers, but the mount did not finish in time. It is usually a wrong password; if it keeps happening, restart NetAuth.")
        case .invalidAddress:
            String(localized: "Check the server’s address and the share’s path.")
        case .other(let message):
            message
        }
    }
}
