import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pasella/constants/layout_constants.dart';
import 'package:pasella/services/firestore_service.dart';
import 'package:pasella/shared/widgets/custom_app_bar.dart';
import 'package:pasella/shared/widgets/custom_text_button.dart';
import 'package:pasella/shared/widgets/custom_text_field.dart';

class EditTransactionScreen extends StatefulWidget {
  final String customerName;
  final String customerId;
  final String transactionId;
  final Map<String, dynamic> transaction;

  EditTransactionScreen({
    required this.customerName,
    required this.customerId,
    required this.transactionId,
    required this.transaction,
  });

  @override
  _EditTransactionScreenState createState() => _EditTransactionScreenState();
}

class _EditTransactionScreenState extends State<EditTransactionScreen> {
  final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';
  final _formKey = GlobalKey<FormState>();
  final _fireStoreService = FirestoreService();
  TextEditingController _amountController = TextEditingController();
  TextEditingController _remarksController = TextEditingController();
  DateTime _selectedDate = DateTime.now();
  DateTime _repaymentDate = DateTime.now().add(Duration(days: 30));
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _amountController.text = widget.transaction['amount'].toString();
    _remarksController.text = widget.transaction['remarks'];
    _selectedDate = DateTime.parse(widget.transaction['date']);
    if (widget.transaction['type'] == 'Credit') {
      _repaymentDate = widget.transaction['repaymentDate'].toDate();
    }
  }

  bool _validateAmount() {
    if (_amountController.text.isEmpty ||
        double.tryParse(_amountController.text) == null) {
      return false;
    }
    return true;
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : Colors.green,
    ));
  }

  Future<void> _editTransaction() async {
    if (!_formKey.currentState!.validate() ||
        !_validateAmount() ||
        _isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
    });

    // Step 2: Update your Firestore Reference
    DocumentReference transactionRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId)
        .collection('customers')
        .doc(widget.customerId)
        .collection('transactions')
        .doc(widget.transactionId);

    var updatedTransactionData = {
      'amount': double.parse(_amountController.text),
      'date': _selectedDate,
      'remarks': _remarksController.text,
      'repaymentDate': _repaymentDate,
      'status': widget.transaction['status'],
      'type': widget.transaction['type'],
    };

    DocumentSnapshot snapshot = await transactionRef.get();

    if (!snapshot.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Failed to update transaction: Transaction does not exist.'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 2),
        ),
      );
      Navigator.pop(context);
    } else {
      try {
        await transactionRef.update(updatedTransactionData);

        // Step 3: Check and possibly update the Last Transaction
        DocumentReference customerRef = FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .collection('customers')
            .doc(widget.customerId);

        DocumentSnapshot customerSnapshot = await customerRef.get();

        if (customerSnapshot.exists) {
          var customerData = customerSnapshot.data() as Map<String, dynamic>;
          var lastTransactionDate =
              (customerData['lastTransaction']['date'] as Timestamp).toDate();

          DateTime truncatedSelectedDate = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _selectedDate.hour,
              _selectedDate.minute,
              _selectedDate.second);
          DateTime truncatedLastTransactionDate = DateTime(
              lastTransactionDate.year,
              lastTransactionDate.month,
              lastTransactionDate.day,
              lastTransactionDate.hour,
              lastTransactionDate.minute,
              lastTransactionDate.second);

          if (truncatedLastTransactionDate == truncatedSelectedDate) {
            await customerRef
                .update({'lastTransaction': updatedTransactionData});
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Transaction updated successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        _fireStoreService.triggerBalanceCalculation();

        Navigator.pop(context);
      } catch (e) {
        print('Error while updating the transaction: $e');

        // Optionally, inform the user about the error using a UI element.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update the transaction: $e'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 3),
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: CustomAppBar(
          title:
              'Edit ${widget.transaction['type'] == 'Credit' ? 'Credit' : 'Payment'} for ${widget.customerName}'),
      body: SafeArea(
        child: Padding(
          padding: LayoutConstants.padding20Horizontal,
          child: Form(
            key: _formKey,
            child: ListView(
              // Using ListView to avoid overflow issues
              children: [
                CustomTextField(
                    label: 'Amount',
                    hintText: 'Enter Amount',
                    prefixIcon: Icons.money,
                    controller: _amountController,
                    textInputType: TextInputType.number,
                    validator: (value) {
                      if (value!.isEmpty || double.tryParse(value) == null) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    }),
                SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      'Date: ',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    SizedBox(width: 10),
                    ElevatedButton(
                      onPressed: () async {
                        DateTime? pickedDate = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2000),
                          lastDate: DateTime.now(),
                        );
                        if (pickedDate != null && pickedDate != _selectedDate) {
                          setState(() {
                            _selectedDate = pickedDate;
                          });
                        }
                      },
                      child: Text('${_selectedDate.toLocal()}'.split(' ')[0]),
                    ),
                  ],
                ),
                if (widget.transaction['type'] == 'Credit') ...[
                  SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Repayment Date: ',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      SizedBox(width: 10),
                      ElevatedButton(
                        onPressed: () async {
                          DateTime? pickedDate = await showDatePicker(
                            context: context,
                            initialDate: _repaymentDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null &&
                              pickedDate != _repaymentDate) {
                            setState(() {
                              _repaymentDate = pickedDate;
                            });
                          }
                        },
                        child:
                            Text('${_repaymentDate.toLocal()}'.split(' ')[0]),
                      ),
                    ],
                  ),
                ],
                SizedBox(height: 16),
                TextFormField(
                  controller: _remarksController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Remarks/Notes',
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 16),
                Stack(alignment: Alignment.center, children: [
                  CustomButton(
                    title: 'Update ${widget.transaction['type']}',
                    onTap: _isLoading
                        ? () => null
                        : () async {
                            await _editTransaction();
                          },
                    color: widget.transaction['type'] == 'Credit'
                        ? Colors.red
                        : Colors.green,
                    icon: widget.transaction['type'] == 'Credit'
                        ? Icons.arrow_downward
                        : Icons.arrow_upward,
                  ),
                  if (_isLoading)
                    CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white))
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
