# Jentra mobile companion apps

These terms describe the employee and field-sales workflows shared with Jentra OS.

## People

**Employee**: A person with an employment record in a Jentra legal entity. An employee is not automatically an application user.
_Avoid_: login, user account

**User account**: The authenticated identity used to access Jentra. Its business access comes from active membership, permissions and verified links.
_Avoid_: employee record

**Employee account link**: An explicitly proposed and accepted association between a user account and an employee record. The link itself does not grant self-service or payroll access.
_Avoid_: email match, automatic login association

**Supervisor**: A user with effective responsibility for specified employees and explicitly delegated approval authority. Job title alone does not establish approval authority.
_Avoid_: unrestricted manager

## Sales

**Salesman**: A user authorized to sell to a defined customer portfolio for specified Jentra entities and branches. The UI may use the more inclusive role label Sales representative.
_Avoid_: tenant-wide sales administrator

**Customer assignment**: A dated grant of responsibility and access to a customer portfolio. An order's salesperson field records attribution and is not an access grant.
_Avoid_: salesperson label, ownership filter

**Customer acceptance**: The customer's attributable acceptance of one specific quotation or order revision and its commercial terms.
_Avoid_: company approval, stock reservation

**Company approval**: An authorized Jentra decision allowing an order to proceed under current commercial and credit policy. An order on credit hold has not received this approval.
_Avoid_: customer acceptance

**Stock reservation**: An allocation of available stock to order lines. It does not prove picking, dispatch or physical delivery.
_Avoid_: delivered stock

**Delivery acknowledgement**: Attributable evidence of quantities received, refused or short by the customer for a specific delivery.
_Avoid_: stock posting, automatic invoice

**Collection submission**: A salesman's report of cash, cheque or transfer evidence received from a customer, awaiting the applicable finance/custody process.
_Avoid_: cleared payment, reconciled receipt

**Posted receipt**: A finance-authorized accounting fact recording a customer payment. Its allocations and bank reconciliation remain separately identifiable.
_Avoid_: photo of payment, transfer screenshot
