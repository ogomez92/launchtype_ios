import CoreTransferable
import UniformTypeIdentifiers

/// The exported backup for `ShareLink`: the zip is only built when the user
/// actually picks a share destination.
struct BackupArchive: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { _ in
            SentTransferredFile(try DataArchive.exportZip())
        }
    }
}
