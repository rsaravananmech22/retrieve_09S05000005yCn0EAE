/**********************************************************************
Name: HDMDealerExperienceController
Purpose: Apex class is created for insertion/updation of external objects & fields for HDM org.
Created Date :  30/07/2021, 3:01 PM
Created By : Vikrant Upneja
Last Modified By :	Faraz Ansari 25/05/2022 for 8722
Last Modified By :	RajRishi Kaushik ,  06/06/2022, 11:19 AM
Salesforce API Version : 55.0
*************************************************************/
public class HDMDealerExperienceController {
    @TestVisible private static List<Order__x> mockedOrder = new List<Order__x>();
    @TestVisible private static List<OrderItem__x> mockedOrderItems = new List<OrderItem__x>();
    @TestVisible private static List<Account__x> mockedAccounts = new List<Account__x>();
    
    @auraEnabled
    public static Order__x updateExternalOrder(Order__x objOrder){
        system.debug('Order__x : '+objOrder);
        if(objOrder != null){
            try{ 
                if(!Test.isRunningTest())
                	Database.updateImmediate(objOrder);
                return objOrder;
            }catch(Exception ex){
                System.debug('Exception Occurred : '+ ex.getMessage());             
            }            
        }
        return null;       
    } 
    
    @auraEnabled
    public static List<OrderItem__x> updateExternalOrderItem(List<OrderItem__x> lstOrderItems, String orderStatus, Decimal restockingFees, Decimal shippingRefund, Decimal installRefund, Decimal TaxRefund, String customerNote){
        system.debug('lstOrderItems : '+lstOrderItems);
        if(!lstOrderItems.isEmpty()){
            try{ 
                String OrderId = (!mockedOrder.isEmpty()) ? 'mocked' : lstOrderItems[0].OrderId__c;              
                if(String.isNotBlank(OrderId)){
                    System.debug('OrderId' + OrderId);
                    Order__x objOrder = (!mockedOrder.isEmpty()) ? mockedOrder[0] : [SELECT Id,ShippingStreet__c, Total_Current_Product_Tax_c__c, Total_Current_Pre_Tax_Order_Amount_c__c, Current_Quantity_c__c, ShippingCity__c, ShippingState__c, ShippingCountry__c, ShippingPostalCode__c, Current_Installation_Tax_c__c, ExternalId, AccountId__c,Customer_Notes_c__c,
                                                                                     Updated_Shipping_c__c, Updated_Total_Tax_c__c, Updated_Order_Total_c__c, Status__c, Updated_Order_Amount_c__c, Send_Email_To_Customer_c__c, Shipping_Refund_c__c, Restocking_Fees_c__c, Install_Refund_c__c, Tax_Refund_c__c,
                                                                                     Cart_Shipping_Street_c__c, Cart_Shipping_City_c__c, Cart_Shipping_State_c__c, Cart_Shipping_Postal_Code_c__c, Total_Return_c__c, Total_Tax_Return_c__c, Total_Item_Return_c__c, OrderedDate__c
                                         FROM Order__x
                                         WHERE Id =: OrderId];
                    System.debug('objOrder' + objOrder);
                    if(orderStatus == 'Modify Order'){
                        List<B2B_VertexTaxCalculationIntegration.OrderItemWrapper> lstOrderItemWrappers = new List<B2B_VertexTaxCalculationIntegration.OrderItemWrapper>();              
                        Decimal updatedAmount = 0;
                        Decimal updatedTax = 0;
                        for(OrderItem__x objOrderItem : lstOrderItems){    
                            B2B_VertexTaxCalculationIntegration.OrderItemWrapper objOrderItemWrapper = new B2B_VertexTaxCalculationIntegration.OrderItemWrapper();
                            if(objOrderItem.Delta_Quantity_c__c > 0){
                                objOrderItemWrapper.quantity = Integer.valueOf(objOrderItem.Delta_Quantity_c__c); 
                                objOrderItemWrapper.unitPrice =  (!Test.isRunningTest()) ? objOrderItem.ListPrice__c : 22.00;
                                objOrderItemWrapper.orderItemId = objOrderItem.Id;
                                lstOrderItemWrappers.add(objOrderItemWrapper);
                            }            
                            if(!Test.isRunningTest()){
                                updatedAmount += objOrderItem.Delta_Quantity_c__c * objOrderItem.ListPrice__c;   
                            }                                                     
                        }
                        
                        String taxResponse = B2B_TaxHelper.getTaxRatesAndAmountsFromVertex(objOrder, lstOrderItemWrappers, null, null, null);
                        B2B_VertexTaxCalculationIntegration.ResponseDataWrapper responseData = (B2B_VertexTaxCalculationIntegration.ResponseDataWrapper) JSON.deserialize(taxResponse, B2B_VertexTaxCalculationIntegration.ResponseDataWrapper.class);
                        System.debug('Vertex Tax :-' + responseData);
                        if(responseData.isSuccess == true){
                            Decimal currentQuantity = 0;
                            // changes for HDMP-8716 : audit trail starts
                            for(OrderItem__x objOrderItem : lstOrderItems){ 
                                if(responseData.mapOrderItemTax.containsKey(objOrderItem.Id)){
                                    Decimal productTax = -1 * responseData.mapOrderItemTax.get(objOrderItem.Id);
                                    objOrderItem.Total_Current_Product_Tax_c__c = objOrderItem.Total_Current_Product_Tax_c__c - productTax;
                                    objOrderItem.Total_Return_Product_Tax_c__c = productTax;
                                }     
                                currentQuantity += objOrderItem.Delta_Quantity_c__c;
                            }
                            // changes for HDMP-8716 : audit trail ends
                            
                            updatedTax = -1 * responseData.totalTaxAmount;
                            decimal totalUpdated = updatedAmount + updatedTax;
                            objOrder.Updated_Order_Amount_c__c = objOrder.Updated_Order_Amount_c__c - updatedAmount;
                            objOrder.Updated_Total_Tax_c__c = objOrder.Updated_Total_Tax_c__c - updatedTax;
                            objOrder.Updated_Order_Total_c__c = objOrder.Updated_Order_Total_c__c - totalUpdated;
                            objOrder.Customer_Notes_c__c = customerNote;// Added by Faraz for 8722
                            objOrder.Restocking_Fees_c__c = 0;
                            
                            //added for HDMP-10890
                            objOrder.Current_Quantity_c__c = objOrder.Current_Quantity_c__c - currentQuantity;
                            objOrder.Total_Current_Pre_Tax_Order_Amount_c__c = objOrder.Updated_Order_Total_c__c - objOrder.Updated_Total_Tax_c__c;
                            objOrder.Total_Current_Product_Tax_c__c = objOrder.Total_Current_Product_Tax_c__c - updatedTax;
                            
                            if(objOrder.Updated_Order_Amount_c__c == 0){
                                objOrder.Updated_Order_Total_c__c = 0;
                                objOrder.Updated_Shipping_c__c = 0;
                                objOrder.Status__c = 'CUSTOMER CANCELED'; 
                            } 
                        }else {
                            return null;
                        }
                        

                    }else if(orderStatus == 'Partial Return'){
                        objOrder.Status__c = 'PARTIAL RETURN COMPLETE';
                        objOrder.Send_Email_To_Customer_c__c = false;
                        objOrder.Shipping_Refund_c__c = shippingRefund;
                        objOrder.Restocking_Fees_c__c = restockingFees;
                        objOrder.Install_Refund_c__c = installRefund;
                        objOrder.Tax_Refund_c__c = TaxRefund;
                        objOrder.Customer_Notes_c__c = customerNote;// Added by Faraz for 8722
                    }
                    if(!Test.isRunningTest()){
                       //update orderItem
                        Database.updateImmediate(lstOrderItems);
                        //update order                
                        Database.updateImmediate(objOrder);  
                    }                   
                }
                
                return lstOrderItems;
            }catch(Exception ex){
                System.debug('Exception Occurred : '+ ex.getMessage());
                System.debug('Exception Line Number : '+ ex.getLineNumber());
                System.debug('Exception Line Number : '+ ex.getStackTraceString());
            }            
        }
        return null;       
    } 
    
    @AuraEnabled
    public static OrderWrapper OrderDetails(String recordId){
        OrderWrapper objOrderWrapper = new OrderWrapper();
        objOrderWrapper.isDealerAdmin = false;
        system.debug('recordid is'+ recordId);
        String userid = UserInfo.getUserId();
        List<PermissionSetAssignment> lstPermissionSets = [SELECT Id, PermissionSetId, PermissionSet.Name, AssigneeId, Assignee.Name 
                                                           FROM PermissionSetAssignment 
                                                          WHERE AssigneeId =: userid AND (PermissionSet.Name = 'DreamShop_Order_Managemnt' OR PermissionSet.Name = 'DreamShop_Order_General' OR PermissionSet.Name ='HELMS_and_HDM_Manager' )];
        if(!lstPermissionSets.isEmpty()){
            for(PermissionSetAssignment objPermission : lstPermissionSets){
               if(objPermission.PermissionSet.Name == 'DreamShop_Order_Managemnt' || objPermission.PermissionSet.Name == 'HELMS_and_HDM_Manager'){
                    objOrderWrapper.isDealerAdmin = true;
                }   
            }
        }
        //R2B changes for HDMP-10201 : added OrderReferenceNumber__c in Query
        List<Order__x> orderlist = (!mockedOrder.isEmpty()) ? mockedOrder : [SELECT Id, OrderReferenceNumber__c, Payment_Type_c__c, Tax_Refund_c__c, AccountId__c, Install_Refund_c__c, Total_Installation_Charges_c__c, Is_Shipping_Returned_c__c, Total_Installation_Return_c__c, Total_Return_c__c, Total_Item_Return_c__c, Total_Ship_Return_c__c, Updated_Shipping_c__c, Total_Tax_Return_c__c, Total_Restocking_Fees_c__c, Shipping_Refund_c__c, Restocking_Fees_c__c, 
                                   AccountId__r.IsActive_c__c, AccountId__r.Charge_Restocking_Fees_c__c, AccountId__r.Return_Window_c__c, AccountId__r.Restocking_Fees_c__c, AccountId__r.Restocking_Fees_Percentage_c__c, AccountId__r.Restocking_Fees_Type_c__c, Shipped_Date_c__c, Dealer_Shipping_Speed_c__c, Customer_Preferred_Speeds_c__c, 
                                   Total_Installation_Charge_c__c, Delivery_Types_c__c, isOrderPickedUp_c__c, CC_Last4_c__c, Customer_Name_c__c, Other_Carrier_c__c, BT_Transaction_Id_c__c, Vertex_Trans_Id_c__c, OrderNumber__c, IsError_c__c, Name__c, BillingPhoneNumber__c,BT_Transaction_Status_c__c,TotalTaxAmount__c,
                                   Cart_Shipping_Customer_Name_c__c, Cart_Shipping_Phone_c__c, ShippingStreet__c, ShippingCity__c, ShippingState__c, ShippingCountry__c, ShippingPostalCode__c,Customer_Notes_c__c,
                                   Phone_No_c__c,Status__c,Shipping_Vendors_c__c,OrderedDate__c,Email_c__c,BillingStreet__c,BillingCity__c,BillingState__c,
                                   BillingZip_c__c,Account_Name_c__c,ShippingNumber_c__c,ORDER_AMOUNT_from_cart_c__c,SHIPPING_from_cart_c__c,TAX_from_cart_c__c,
                                   TOTAL_from_cart_c__c,IsPaymentReproccessing_c__c ,Updated_Total_Tax_c__c, Updated_Order_Total_c__c, Updated_Order_Amount_c__c,
                                   Send_Email_To_Customer_c__c,BillingEmailAddress__c, (SELECT Id, Total_Return_Installation_Charge_c__c, Total_Current_Product_Tax_c__c,Total_Return_Product_Tax_c__c, Dealer_Installation_Price_c__c, Delta_Installation_Price_c__c, Product2Id__c, Cart_Item_Product_Name_c__c,Product_Name_c__c,Product_SKU_c__c,Type__c ,Quantity__c,ListPrice__c,Order_Item_Status_c__c,
                                    Updated_Quantity_c__c, Return_Quantity_c__c,Delta_Quantity_c__c, OrderId__c,Total_Tax_c__c,Product_Model_Marketing_Name_c__c 
                                    FROM Order_Products__r WHERE Type__c != 'Delivery Charge' Order by Product_SKU_c__c), 
                                    (SELECT Id, Dealer_To_Customer_Note_c__c, CreatedDate__c FROM Order_Transactions__r WHERE Order_Transaction_Status_c__c = 'Success' Order By CreatedDate__c DESC)                                    
                                   FROM Order__x 
                                   WHERE Id=:recordId];
        system.debug('orderlist is'+orderlist);        
        if(!orderlist.isEmpty()){
            objOrderWrapper.lstOrders = orderlist;
            return objOrderWrapper;
        }
        return null;           
    }  
       
    @AuraEnabled
    public static OrderWrapper getAccountDetails(){
        OrderWrapper objOrderWrapper = new OrderWrapper();
        objOrderWrapper.isDealerAdmin = false;   
        objOrderWrapper.lstCarriers = new List<Carrier_c__x>();
        
        String userid = UserInfo.getUserId();
        List<PermissionSetAssignment> lstPermissionSets = [SELECT Id, PermissionSetId, PermissionSet.Name, AssigneeId, Assignee.Name 
                                                           FROM PermissionSetAssignment 
                                                          WHERE AssigneeId =: userid AND (PermissionSet.Name = 'DreamShop_Order_Managemnt' OR PermissionSet.Name = 'DreamShop_Order_General' OR PermissionSet.Name ='HELMS_and_HDM_Manager' )];
        if(!lstPermissionSets.isEmpty()){
            for(PermissionSetAssignment objPermission : lstPermissionSets){
               if(objPermission.PermissionSet.Name == 'DreamShop_Order_Managemnt' || objPermission.PermissionSet.Name == 'HELMS_and_HDM_Manager'){
                    objOrderWrapper.isDealerAdmin = true;
                }   
            }
        }
                
        String contactid;
        String dealercode;       
        List<Account__x> accountList;        
        List<User> usrLst = new List<user>();
        if(!String.isEmpty(userid)){           
            usrLst = [SELECT ContactId from User WHERE Id=:userid];
            contactid=usrLst.get(0).ContactId;
        }
        
        if(!String.isEmpty(contactid)){
            List<Contact> dealercodelst = new List<Contact>();
            dealercodelst= [SELECT Account.DealerCode_CD__c FROM Contact WHERE Id=:contactid];
            dealercode=dealercodelst.get(0).Account.DealerCode_CD__c;           
            accountList = (!mockedAccounts.isEmpty()) ? mockedAccounts : [SELECT Id, Preferred_Shipping_Carrier_c__c, Service_Scheduling_URL_c__c, Return_Window_c__c, Charge_Restocking_Fees_c__c,
                      Restocking_Fees_c__c, Restocking_Fees_Percentage_c__c, Restocking_Fees_Type_c__c
                      FROM Account__x 
                      WHERE PoIId_c__c =: dealercode];
            if(!accountList.isEmpty())
                objOrderWrapper.lstAccounts = accountList;
            System.debug('accountList : '+accountList);
            
            objOrderWrapper.lstCarriers = [SELECT Id, ExternalId, Name__c, OwnerId__c FROM Carrier_c__x];
            
        }
        return objOrderWrapper;
    }
    
    @AuraEnabled
    public static Account__x updateDealerAccount(Account__x objAccount){         
        if(objAccount != null){
            Long beforeAPI = B2B_Util.fetchCurrentTime();
            try{
                 if(!Test.isRunningTest())
                 	Database.updateImmediate(objAccount);
            }catch(exception ex){
                Long afterAPI = B2B_Util.fetchCurrentTime();
                Long durationTime = B2B_Util.calInMilliSeconds(beforeAPI,afterAPI);
                B2B_Util.createErrorRecord('','',objAccount.ExternalId,'','','HDMDealerExperienceController', ex.getMessage(),Label.B2B_Error_Type,'','updateDealerAccount',true, '','','',durationTime,Label.B2B_Severity,'','');
                
                System.debug('Exception :'+ ex.getMessage());
            }
           
        }       
        return objAccount;
    }

    //Added by Faraz for 8722 on 25/05/22 - start
    @AuraEnabled
    public static string addExternalDealerNotes(String orderId, String dealerNote){
        try {
            Dealer_Notes_c__x notesObj = new Dealer_Notes_c__x();
            notesObj.Order_c__c = orderId;
            notesObj.Notes_c__c = dealerNote;
            notesObj.Created_By_Name_c__c = UserInfo.getName();
            //insert notesObj;
            if(!Test.isRunningTest()){
                Database.insertImmediate(notesObj);
                return 'Note Added';
            }
            return 'Insertion Failed';
        } catch (Exception e) {
            System.debug('Exception :'+ e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    public static string getAllExternalDealerNotes(String orderId){
        try {
            return JSON.serialize([SELECT Id, (SELECT Id, Order_c__c, Notes_c__c, CreatedDate__c, Created_By_Name_c__c FROM Dealers_Notes__r Order by CreatedDate__c DESC)  FROM Order__x Where id =: orderId]);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    //Added by Faraz for 8722 on 25/05/22 - end
    
    public class OrderWrapper {
        @AuraEnabled public boolean isDealerAdmin;
        @AuraEnabled public List<Order__x> lstOrders;
        @AuraEnabled public List<Account__x> lstAccounts;   
        @AuraEnabled public List<Carrier_c__x> lstCarriers;   
    }
}