import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';

abstract class LibraryRepository {
  Future<List<LibraryItem>> getItems({int limit = 1000, int offset = 0});
  Future<void> addItem(LibraryItem item);
  Future<void> updateItem(LibraryItem item);
  Future<void> deleteItem(String code);
  
  // History
  Future<List<Map<String, dynamic>>> getHistory({int limit = 20, int offset = 0});
  Future<void> addHistoryEntry(Map<String, dynamic> entry);
  Future<LibraryItem?> getItemByBarcode(String barcode);
  // Statistics
  Future<Map<String, dynamic>> getStats();

  // Code Definitions (Variables)
  Future<List<Map<String, dynamic>>> getCodeDefinitions();
  Future<void> addCodeDefinition(String prefix, String label);
  Future<void> updateCodeDefinition(String oldPrefix, String newPrefix, String label);
  Future<void> deleteCodeDefinition(String prefix);

  // Attribute Definitions
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type);
  Future<void> addAttributeDefinition(String type, String value);
  Future<void> deleteAttributeDefinition(int id);

  // Members
  Future<List<Member>> getMembers();
  Future<void> addMember(Member member);
  Future<void> updateMember(Member member);
  Future<void> deleteMember(String memberId);

  // Loans
  Future<List<Loan>> getLoans({bool activeOnly = false});
  Future<void> addLoan(Loan loan);
  Future<void> updateLoan(Loan loan); // For returns/renewals
}
