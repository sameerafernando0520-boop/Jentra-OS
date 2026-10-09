-- PREPARED ONLY. No synthetic account or business bootstrap is authorized yet.
-- Execute only after the final bound review SHA and explicit owner approval.
-- Auth users must be created through Auth Admin first, with random private
-- passwords, email_confirm=true and no email delivery. Never INSERT auth.users.
-- Resolve only the six reviewed labels; any collision/preexisting user aborts
-- in the Auth provisioning preflight and requires a refreshed owner review.
begin;
create temporary table w5_runtime_accounts(label text primary key,user_id uuid not null unique,email text not null unique);
insert into w5_runtime_accounts
 select labels.label,u.id,u.email from(values
 ('proposer','w5-proposer@jentra.invalid'),
 ('approver','w5-approver@jentra.invalid'),
 ('executor','w5-executor@jentra.invalid'),
 ('billing-admin','w5-billing-admin@jentra.invalid'),
 ('operator','w5-operator@jentra.invalid'),
 ('foreign-member','w5-foreign-member@jentra.invalid')) labels(label,email)
 join auth.users u on lower(u.email)=labels.email and u.deleted_at is null;
do $$begin if (select count(*) from w5_runtime_accounts)<>6 then raise exception 'EXACT_SIX_AUTH_ACCOUNTS_REQUIRED';end if;end$$;
create temporary table w5_runtime_scopes(key text primary key,tenant_id uuid not null,entity_id uuid not null,branch_id uuid not null,second_branch_id uuid,slug text not null,plan_code text not null);
insert into w5_runtime_scopes values
 ('runtime','babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,'3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid,'ed14db1b-8088-4e4d-89e0-34da88d2d769'::uuid,'jentra-w5-runtime-20261008','w5_runtime_20261008'),
 ('foreign','c1ae4d89-6379-45ef-8ee8-1779593eb8d9'::uuid,'2a082915-10ed-47a1-8985-8c0368b53116'::uuid,'5de9d678-48af-4db1-8310-f367bb53088d'::uuid,null,'jentra-w5-foreign-20261008','w5_foreign_20261008'),
 ('load-001','4b619cd7-adde-4c04-8526-f1170a32a25a'::uuid,'3a5f986d-0bde-4a4a-88cd-672f90c8783e'::uuid,'01d6b6bf-f6d7-4819-84d4-f193acfe5012'::uuid,null,'jentra-w5-load-001-20261008','w5_quota10_20261008'),
 ('load-002','3d63eec9-3672-460a-8927-6aa4217b81a1'::uuid,'f277efa6-1e45-4ac5-835b-3bcac73a742b'::uuid,'8bfe1e58-9362-4c46-8306-42934dddbea1'::uuid,null,'jentra-w5-load-002-20261008','w5_load_20261008'),
 ('load-003','bad6b00f-7d96-4918-8870-00ce7f51ef86'::uuid,'057b0f25-f9ea-430c-8ae3-2eab1656a132'::uuid,'35b6d61c-9c5a-40c2-81c3-7fdd3b4e7221'::uuid,null,'jentra-w5-load-003-20261008','w5_load_20261008'),
 ('load-004','799e67c7-faa4-44fb-8c4e-29973a7fefc1'::uuid,'7c37809e-e92e-4ea0-8eef-52407f53eac3'::uuid,'1423a87e-0ec7-4986-82ac-66dfea1fb247'::uuid,null,'jentra-w5-load-004-20261008','w5_load_20261008'),
 ('load-005','f1076664-74fd-4972-85b6-6b246897c39e'::uuid,'38b79564-ae39-4920-888f-a8fa9f1b3fc2'::uuid,'41bc1a68-29da-49c3-8dd8-b388eb1c11b5'::uuid,null,'jentra-w5-load-005-20261008','w5_load_20261008'),
 ('load-006','7cef392b-990d-41eb-8283-4158144bb1a6'::uuid,'d45918ba-3ea7-461f-8cd5-a9db0d082472'::uuid,'d11f8b72-e152-445a-820f-b32cdc680627'::uuid,null,'jentra-w5-load-006-20261008','w5_load_20261008'),
 ('load-007','fd27109c-dbc6-46d9-8a30-b3ac9cffefb6'::uuid,'a5626bb6-9cad-4f8a-8cf9-5f3ded887d94'::uuid,'c34cf851-da92-4713-83bb-2d3f2a42287e'::uuid,null,'jentra-w5-load-007-20261008','w5_load_20261008'),
 ('load-008','c2eaf879-3a6c-4136-8a65-8906e3b69aaf'::uuid,'648da975-f935-4468-8dc0-6c83274c5be8'::uuid,'f405d449-add4-4890-85a2-d1250002d316'::uuid,null,'jentra-w5-load-008-20261008','w5_load_20261008'),
 ('load-009','b3def46f-e903-4aa4-84eb-d16fdc8a48f6'::uuid,'b58398b2-2f89-42b2-8771-2fab7310ae8e'::uuid,'d5ce055b-3daa-4a9d-8cd1-ab136cb99146'::uuid,null,'jentra-w5-load-009-20261008','w5_load_20261008'),
 ('load-010','7a5fdc78-16ee-40c9-81bf-ec5e822dc6e8'::uuid,'8482e2bf-3316-4c28-8ef5-9a090ca4f92a'::uuid,'58a4ed4c-f8ec-4a25-8c87-f630fd1ee2fc'::uuid,null,'jentra-w5-load-010-20261008','w5_load_20261008'),
 ('load-011','193b8936-a775-4e27-88bb-e277339c99c0'::uuid,'680540c6-98ec-45d3-8ec5-6bf3e70fcb4c'::uuid,'7621cdcd-f178-49c0-8db9-c6b95a136c6d'::uuid,null,'jentra-w5-load-011-20261008','w5_load_20261008'),
 ('load-012','765a971d-f59e-4326-8332-088d8af6263f'::uuid,'20552bdc-8286-4126-89e4-9a84da3ff9b6'::uuid,'5b6a514c-34e1-4f03-86f4-22b04dc8fda9'::uuid,null,'jentra-w5-load-012-20261008','w5_load_20261008'),
 ('load-013','af36525b-3909-4cb3-894d-8a93506b0260'::uuid,'1a960736-1feb-4eca-8c28-aa9bc951455f'::uuid,'bcf81b65-fd8d-4cd2-8c8b-dce5c6113ebe'::uuid,null,'jentra-w5-load-013-20261008','w5_load_20261008'),
 ('load-014','ac5d6aee-27e0-4eef-8771-17bfba7e9ec2'::uuid,'2a2c1dec-3218-4005-8913-1bcd35a92578'::uuid,'ac186cc4-4412-4e2c-84e6-6ed652a94355'::uuid,null,'jentra-w5-load-014-20261008','w5_load_20261008'),
 ('load-015','73c0c2c4-5b84-4237-8eda-cf63c9531e01'::uuid,'9cb3d6cd-f1ac-4af2-8288-6319417e5483'::uuid,'3fa470fb-52c1-429f-80b2-82e9ad5a6417'::uuid,null,'jentra-w5-load-015-20261008','w5_load_20261008'),
 ('load-016','94aeb3fe-8170-4d14-8871-63b2a92cd047'::uuid,'2765ab3f-d80c-452c-82bd-1123cdd04237'::uuid,'55a6bcad-43bf-44c0-8b67-2ccbcd948eeb'::uuid,null,'jentra-w5-load-016-20261008','w5_load_20261008'),
 ('load-017','1d4439e5-2c50-47ba-82ae-bb30bf43ae80'::uuid,'440eefcf-b109-4f91-835f-b1d63a50fb64'::uuid,'1fc2f2c1-2180-4b6d-8c0a-e1aecac9cdec'::uuid,null,'jentra-w5-load-017-20261008','w5_load_20261008'),
 ('load-018','0318b048-be76-47d9-842c-a287251ff27d'::uuid,'90d9b2de-e24b-4909-896f-d5344dc771d2'::uuid,'0a15a819-d829-4509-859a-07aace7b0f0a'::uuid,null,'jentra-w5-load-018-20261008','w5_load_20261008'),
 ('load-019','d07c6612-a7fd-4f06-8629-ae202c6ed8e2'::uuid,'97eb2a6a-7b6b-4d46-88c4-ab0cc3ee1140'::uuid,'cbe40ba1-7094-4962-839b-1d1743ceb612'::uuid,null,'jentra-w5-load-019-20261008','w5_load_20261008'),
 ('load-020','39c1cfa0-7b12-4b61-8ac6-f21d011f088d'::uuid,'8e2a76bc-2e3a-4e85-8b5c-66ed2eebe3bc'::uuid,'c3d4c6ef-094c-43db-8289-460adad3272a'::uuid,null,'jentra-w5-load-020-20261008','w5_load_20261008'),
 ('load-021','39d45a2f-bc2a-4b14-82b7-4d77c8256b42'::uuid,'911066e3-9786-4049-85ab-f9e74c207994'::uuid,'a46ddc69-1f29-437c-8650-8160d1a05e3f'::uuid,null,'jentra-w5-load-021-20261008','w5_load_20261008'),
 ('load-022','4b2b7361-8492-4a69-856b-95aa4b41f275'::uuid,'8eeaf59c-ea4d-4f4f-8956-4a36a5900f15'::uuid,'388f6011-2faa-4269-823b-fc85d07ac239'::uuid,null,'jentra-w5-load-022-20261008','w5_load_20261008'),
 ('load-023','6ec05bf5-56db-427e-8b81-e81aab5d1bf4'::uuid,'aaccdf70-c974-4f99-88b7-2f2ccbf0bd28'::uuid,'cd7c2066-dbd7-4d27-8cdc-6c891dc4c9a2'::uuid,null,'jentra-w5-load-023-20261008','w5_load_20261008'),
 ('load-024','33c091d5-01fa-41d6-8058-43bc6242a804'::uuid,'5e2f0d8b-4f0a-4cd6-888c-9feb4462d6a8'::uuid,'ec57ac55-8b23-4c4b-884b-15f35938ae91'::uuid,null,'jentra-w5-load-024-20261008','w5_load_20261008'),
 ('load-025','f732e7bb-5f16-4ece-8abe-608bceccbc44'::uuid,'2ded0af0-17bf-41f4-83c7-b4dcffcf4136'::uuid,'c6e1f71e-6f0c-4a36-86aa-0c18f6a4a81a'::uuid,null,'jentra-w5-load-025-20261008','w5_load_20261008'),
 ('load-026','04d9c5b2-085e-4de8-824c-dcb7e88b7a3f'::uuid,'ba3b7101-9f87-4e10-8e50-dec347e16b17'::uuid,'39606e18-e1eb-46e5-866a-7fd682e08159'::uuid,null,'jentra-w5-load-026-20261008','w5_load_20261008'),
 ('load-027','982e2e32-bc0e-4de9-8c43-282dbcc8e5f0'::uuid,'edf31b32-bdfc-42ec-8480-09b8adf46d80'::uuid,'70bfb4e4-5917-4e2a-8746-98c7e892f99f'::uuid,null,'jentra-w5-load-027-20261008','w5_load_20261008'),
 ('load-028','0a2860ae-b66d-4948-87af-701c8de72463'::uuid,'5590d62e-b6a3-4c8b-831d-188fb0986967'::uuid,'35546762-e761-406a-8027-1bc59a66d347'::uuid,null,'jentra-w5-load-028-20261008','w5_load_20261008'),
 ('load-029','73109a1f-2a7c-4716-8387-941887ce08d7'::uuid,'ff5cc3f8-86dc-4a63-87b5-1984827306a4'::uuid,'49b3a0c2-9b68-42b4-82da-b516edd8f666'::uuid,null,'jentra-w5-load-029-20261008','w5_load_20261008'),
 ('load-030','8baa147b-ff61-460d-865f-19edf11aae03'::uuid,'a25cc5ac-701f-430b-825f-627c50b3fb60'::uuid,'429e00b1-697b-4ae1-8cad-7250ff90eba0'::uuid,null,'jentra-w5-load-030-20261008','w5_load_20261008'),
 ('load-031','39ae6862-dc18-4503-8fc0-1bc2f32c9327'::uuid,'cd81e6eb-5949-4b0a-8329-dc1233e29a30'::uuid,'51b0ea43-d5d4-4c55-8b0e-d79d5ab53efd'::uuid,null,'jentra-w5-load-031-20261008','w5_load_20261008'),
 ('load-032','8a0595a2-abe9-4818-8d55-1d03e47b167a'::uuid,'ea0252df-6198-4fb9-8f85-98691f6db40c'::uuid,'863c4d99-e26b-4fa4-840f-c16dbefb7b1b'::uuid,null,'jentra-w5-load-032-20261008','w5_load_20261008'),
 ('load-033','60990906-5c37-4bb9-85ed-64fd3f93a60f'::uuid,'36b633f8-e192-4de8-8630-67952f4ad302'::uuid,'b382f52d-69c9-4d48-8499-b382435ea4f6'::uuid,null,'jentra-w5-load-033-20261008','w5_load_20261008'),
 ('load-034','8009fd88-3126-4981-87e2-1e4bda8efb7c'::uuid,'a2caaf8a-eaaf-4f76-8acc-781cef2a316f'::uuid,'5d2eaa38-a57c-47a3-8db0-e4dc265fdf5a'::uuid,null,'jentra-w5-load-034-20261008','w5_load_20261008'),
 ('load-035','ce8a7b34-2c24-41c4-8ed3-0b38a8b8995c'::uuid,'65128318-6857-4da7-8369-828129c23959'::uuid,'31e852ed-03ec-4509-8925-f71025bad2a1'::uuid,null,'jentra-w5-load-035-20261008','w5_load_20261008'),
 ('load-036','83233d64-40b3-4ae4-8092-c8fcc36ed720'::uuid,'d2eb8f7f-3fd9-4336-8bf4-526fd6937e64'::uuid,'1ffa77c3-a722-4135-8517-6846e21c2741'::uuid,null,'jentra-w5-load-036-20261008','w5_load_20261008'),
 ('load-037','71500d94-4e44-47c6-8d8d-587486726371'::uuid,'aa4b82e9-6457-4a76-84ae-4696f8c8fc39'::uuid,'d715f0bf-a8f8-46e1-847a-de9d5fabddbe'::uuid,null,'jentra-w5-load-037-20261008','w5_load_20261008'),
 ('load-038','b5799ef0-b2d3-444f-8317-e59e99ca5b15'::uuid,'ad6d75f2-7a8c-4712-8113-ae49a4e046dc'::uuid,'5b5f4dfb-bdb3-4987-8f71-2f531c358577'::uuid,null,'jentra-w5-load-038-20261008','w5_load_20261008'),
 ('load-039','f3125611-bf63-4f6d-827c-88c185e425ec'::uuid,'30d3dc58-1d80-4337-86ae-4f962b8eafba'::uuid,'71978023-a8a7-4b4a-8118-58d5d677532d'::uuid,null,'jentra-w5-load-039-20261008','w5_load_20261008'),
 ('load-040','e717f828-938e-4460-8155-b582ddc83985'::uuid,'ecd60864-2f11-4df5-8895-8e2768fdbb4b'::uuid,'baf1db49-7cb6-4c82-8dba-516d22c3ee9f'::uuid,null,'jentra-w5-load-040-20261008','w5_load_20261008'),
 ('load-041','2135a1a1-f613-4b07-887a-c89ed3dfe3c9'::uuid,'10925297-4623-49d2-8c9d-70cf7f951052'::uuid,'66f18af2-a0a9-40e9-8173-348917faa45f'::uuid,null,'jentra-w5-load-041-20261008','w5_load_20261008'),
 ('load-042','235daf1b-45ce-4008-830d-16eed127884c'::uuid,'83de462b-44fa-488b-80dc-90656fb0840b'::uuid,'8f10121e-1801-426f-8eb3-3b0e2d982d4f'::uuid,null,'jentra-w5-load-042-20261008','w5_load_20261008'),
 ('load-043','d599aa1b-94a3-4e5a-8de6-1db94a1acb85'::uuid,'74646bc8-bd61-48b0-8feb-e5ce5f52d854'::uuid,'3ead3318-3fc0-4cba-88ed-070ca8d64a3e'::uuid,null,'jentra-w5-load-043-20261008','w5_load_20261008'),
 ('load-044','c2a1821a-1bd8-4784-8af2-cbae97fc98d5'::uuid,'4822fad7-d7d5-46c0-83b7-3e5d24a1464b'::uuid,'6b3b116e-0462-4b26-86c6-2d33ab9b7025'::uuid,null,'jentra-w5-load-044-20261008','w5_load_20261008'),
 ('load-045','e086594c-0d93-47f2-808f-99c2efad69c1'::uuid,'e65f72ed-b5e8-45ff-8ed0-930a5bf04fc9'::uuid,'4606ef8a-0e81-4e81-8e49-fdec87204ab5'::uuid,null,'jentra-w5-load-045-20261008','w5_load_20261008'),
 ('load-046','fa80a45a-9c67-452f-8332-7e066c3a409b'::uuid,'0404a1cf-f5cf-4941-80f8-b5aeb6c7a330'::uuid,'ecc3b427-9a98-4ae0-8220-4eb79b1473bf'::uuid,null,'jentra-w5-load-046-20261008','w5_load_20261008'),
 ('load-047','730df1ce-adbd-4657-8488-4d0e3d10d94f'::uuid,'99ddd969-42d5-4b7c-83d8-ab25c8b89960'::uuid,'0d34944b-b549-4db9-8800-56b34f1a29a0'::uuid,null,'jentra-w5-load-047-20261008','w5_load_20261008'),
 ('load-048','9dc7b7fe-999a-4fd8-87ae-fd1e464997f6'::uuid,'4f4e8e59-ea6f-411d-8cd5-2e0df033fd39'::uuid,'17c41398-e8f5-48d3-80e6-7dc5db90bf21'::uuid,null,'jentra-w5-load-048-20261008','w5_load_20261008'),
 ('load-049','89c60c6a-6c39-4f79-8f04-9f414febda7e'::uuid,'259be122-9d27-4f83-8a21-cb3a92e39bb7'::uuid,'2c86bb21-0140-436f-8c2e-ddb475c3432a'::uuid,null,'jentra-w5-load-049-20261008','w5_load_20261008'),
 ('load-050','119bdced-7889-4ac9-80a4-f1d030164ff2'::uuid,'80d302c2-cf90-42a0-8a87-0c7a3a6939d1'::uuid,'fcf7845b-fc5b-4dd2-8cf7-a647412a032b'::uuid,null,'jentra-w5-load-050-20261008','w5_load_20261008'),
 ('load-051','f4294705-e4c5-447b-84fa-fd63863a57b0'::uuid,'9b9e69fe-bf34-414a-87bc-36b8e1632b0a'::uuid,'f739f1ed-b850-491c-8db4-6f557e4752f6'::uuid,null,'jentra-w5-load-051-20261008','w5_load_20261008'),
 ('load-052','14f843cc-bf3e-496a-81d9-d80af5b11df9'::uuid,'602b0f9c-5e73-4c09-8894-02b1a444bd78'::uuid,'79e331b7-bafc-4181-8a78-b475041b9aab'::uuid,null,'jentra-w5-load-052-20261008','w5_load_20261008'),
 ('load-053','5760dec8-ee4c-45bf-8164-a58cc118789f'::uuid,'624bafb7-c037-4461-8fe8-4a7323442931'::uuid,'cc3923a3-744d-484f-8c60-1774c71aed36'::uuid,null,'jentra-w5-load-053-20261008','w5_load_20261008'),
 ('load-054','89b6d90f-63bf-4163-841d-1c03771328fe'::uuid,'ec56e974-20ad-45ba-81f5-bb50041779e8'::uuid,'d3b45b17-ded7-4b32-89c5-055cf3d9a592'::uuid,null,'jentra-w5-load-054-20261008','w5_load_20261008'),
 ('load-055','2e3abc10-b992-4a6d-8ee5-c3cd70857cd1'::uuid,'a1bd4b92-7f30-42c1-897b-2f990074b113'::uuid,'4e626f8f-88dc-438e-84dd-9c0a61f0b842'::uuid,null,'jentra-w5-load-055-20261008','w5_load_20261008'),
 ('load-056','b5a5e0ac-2fb0-4288-83ea-65c102269aed'::uuid,'b0ff917f-0027-4884-8790-881800914dd0'::uuid,'6cd357a8-5f34-4d90-86bb-75e5fa14abc7'::uuid,null,'jentra-w5-load-056-20261008','w5_load_20261008'),
 ('load-057','979f8c5d-2117-4865-83cd-d9b8e966f954'::uuid,'8a51ded1-1d65-446c-8bbf-89287e5d93eb'::uuid,'1a127b2e-cdca-4443-8622-674bd8c7c5e4'::uuid,null,'jentra-w5-load-057-20261008','w5_load_20261008'),
 ('load-058','2acdcf58-ae92-4a91-8e31-bee1307153a2'::uuid,'b8a61635-99a4-4ef9-83b4-9329fbf9f905'::uuid,'a1721bb9-d576-497b-8409-d27657403c16'::uuid,null,'jentra-w5-load-058-20261008','w5_load_20261008'),
 ('load-059','cf3f0118-18e4-4d40-8d2b-b376c166d147'::uuid,'ec633b4a-34e2-4a0f-8f1b-df2d468ee17a'::uuid,'df4fb93f-b2d8-4c3a-8d02-7580b25ed664'::uuid,null,'jentra-w5-load-059-20261008','w5_load_20261008'),
 ('load-060','ca439c21-5e9a-4c59-8965-b129d3dfa27f'::uuid,'991da2af-a573-49b0-83cf-28044cd6de3d'::uuid,'15bf3d0b-9a3c-422b-80e4-28d6ef70d1fb'::uuid,null,'jentra-w5-load-060-20261008','w5_load_20261008'),
 ('load-061','a7ef64a4-cd3e-4055-8211-37db1133862f'::uuid,'f1f70f98-1463-4501-8845-40728827c480'::uuid,'50e236ca-8b24-4f9d-895f-8335d2fde22d'::uuid,null,'jentra-w5-load-061-20261008','w5_load_20261008'),
 ('load-062','89a55823-691b-4660-858d-b0c66cef2516'::uuid,'1a8a1c20-4811-4565-8156-5d1d8f6536b5'::uuid,'5847760b-9e6c-4568-8379-e8f99923ea3e'::uuid,null,'jentra-w5-load-062-20261008','w5_load_20261008'),
 ('load-063','ba85ba9c-3d9b-4b0d-8d54-5175a2fa57b0'::uuid,'d8e4c307-2e0e-4190-8a8e-10ac55b7de7d'::uuid,'122a0d95-2f03-4d41-81c2-d84919e56928'::uuid,null,'jentra-w5-load-063-20261008','w5_load_20261008'),
 ('load-064','afa19958-00fd-4fb5-8026-168f969c0569'::uuid,'49096c65-c6e3-407d-889c-26df5d680849'::uuid,'05160ec0-21cd-4cf1-8aae-9d2738fb456a'::uuid,null,'jentra-w5-load-064-20261008','w5_load_20261008'),
 ('load-065','21f67a70-376a-4231-89f9-5469d311c925'::uuid,'a9fb6826-aa12-4c2d-890d-e175f8d5d843'::uuid,'84ee5eb0-7250-40c3-82d4-6bf0196fe6ec'::uuid,null,'jentra-w5-load-065-20261008','w5_load_20261008'),
 ('load-066','3889353d-a878-446b-88ad-9f530ce1dc00'::uuid,'0aed555c-f7b4-4b42-89be-a0985aaafcb3'::uuid,'b3b93769-5d83-4747-8fc5-dd5163eff381'::uuid,null,'jentra-w5-load-066-20261008','w5_load_20261008'),
 ('load-067','108537a1-6d20-4b4b-8ac0-8994d357a346'::uuid,'ec1f1d6f-797f-4a7f-8bb9-9021724ac342'::uuid,'df37a727-80d4-4c02-8e62-b0bdaaf3a65f'::uuid,null,'jentra-w5-load-067-20261008','w5_load_20261008'),
 ('load-068','d262ad53-6f25-4e09-8a3e-5965d897fb2a'::uuid,'0556d5b9-a67e-4afb-800d-668c84c14866'::uuid,'e8b08cd5-e610-4915-82c0-9baf19f6f6bd'::uuid,null,'jentra-w5-load-068-20261008','w5_load_20261008'),
 ('load-069','7849fb98-c6a3-4ac2-86ef-dfe190fc5cc2'::uuid,'fb2fe2da-8a32-4405-8512-46b81d3aefc5'::uuid,'2b4d202e-52ba-4e04-8014-89115c27792d'::uuid,null,'jentra-w5-load-069-20261008','w5_load_20261008'),
 ('load-070','19a9fe42-74a2-4c9f-87ff-f40bc621bcb1'::uuid,'c8744f02-fa57-4b91-84cf-af4a1005e19c'::uuid,'28e6c993-9e70-48f3-8882-f47b4eea4049'::uuid,null,'jentra-w5-load-070-20261008','w5_load_20261008'),
 ('load-071','5369bf49-2489-42a5-8b2d-c09f856de9ec'::uuid,'4d18914a-1cd3-4798-8f69-5fd09def4ad5'::uuid,'3630e2e1-cf7e-4498-8303-36429a7eae91'::uuid,null,'jentra-w5-load-071-20261008','w5_load_20261008'),
 ('load-072','c774f43e-7c62-4767-83e6-fa39ee7d8d47'::uuid,'f3f52697-4c8b-4b35-879d-7bee2f601ae3'::uuid,'5e771d12-e243-4290-8cca-143c7efd4476'::uuid,null,'jentra-w5-load-072-20261008','w5_load_20261008'),
 ('load-073','1a08deed-969a-46f6-8839-67af79a47b6c'::uuid,'3c2e2c68-e8c9-4811-8cb4-94378973f1fc'::uuid,'3d9ce3ff-42d3-4fe5-8f1d-6db79a496d49'::uuid,null,'jentra-w5-load-073-20261008','w5_load_20261008'),
 ('load-074','734ad325-3274-4b7e-8252-720d8e4bd8a5'::uuid,'4cde1879-961e-4be7-86d4-17c08dc140d4'::uuid,'59dfd5a7-76d7-415f-82c9-ff4196f47307'::uuid,null,'jentra-w5-load-074-20261008','w5_load_20261008'),
 ('load-075','12205cbf-21db-4e55-850c-454389d24397'::uuid,'9fe56c9c-7f28-49f0-8c3a-4d141ec1a433'::uuid,'29b64e40-b211-4ddc-87ec-43d1939da00b'::uuid,null,'jentra-w5-load-075-20261008','w5_load_20261008'),
 ('load-076','09db3ab4-7e88-4824-8eb7-4de2753fc2bd'::uuid,'645bb34d-8a9e-4ce1-8e7a-449c1b2fe850'::uuid,'8b3d98ae-7ae6-40ed-8a8f-091553401dc5'::uuid,null,'jentra-w5-load-076-20261008','w5_load_20261008'),
 ('load-077','e237e287-8b86-4f8a-8269-932c89f25d2e'::uuid,'55944b4f-d44c-46f4-8a27-ae18a062bbe9'::uuid,'edfd3c3c-3168-41f3-8bd7-b7750605aa9a'::uuid,null,'jentra-w5-load-077-20261008','w5_load_20261008'),
 ('load-078','be8415db-6756-4b12-899b-d4881b5adabe'::uuid,'d5bfe876-3a07-4c70-8b8f-17cad3d6a49b'::uuid,'a15159fd-6feb-4190-8074-2fb448d6b4cc'::uuid,null,'jentra-w5-load-078-20261008','w5_load_20261008'),
 ('load-079','6ba39b23-4526-49f2-8f81-9dc04ab4f63a'::uuid,'c489b589-9df2-40f3-80be-8c6b9a25c3d9'::uuid,'5b4bfe7e-0338-42c5-81f1-74e5ef3bf240'::uuid,null,'jentra-w5-load-079-20261008','w5_load_20261008'),
 ('load-080','35833635-9de0-4527-86db-d2326f975890'::uuid,'6f9b1f8f-9767-42af-8531-e8b2638480bd'::uuid,'79cf5812-e2b7-46a6-81b7-7faa01e0e6cf'::uuid,null,'jentra-w5-load-080-20261008','w5_load_20261008'),
 ('load-081','aebf89b2-d8f8-4392-897e-b2afb955e5df'::uuid,'537fe138-bbf5-4dbf-8a6d-550d43493eb2'::uuid,'8dcf5f9e-c112-4178-8e4a-c0eb5330b92b'::uuid,null,'jentra-w5-load-081-20261008','w5_load_20261008'),
 ('load-082','16596e5f-7c3d-4ff8-8a24-0c7ef85274f3'::uuid,'f0f0f708-83f7-48c8-8d0e-8cb91bb2e301'::uuid,'20ab2072-b505-4c5e-8129-85a5ad6e53ed'::uuid,null,'jentra-w5-load-082-20261008','w5_load_20261008'),
 ('load-083','5ead7647-02a5-4d3e-8691-ef2c3829cbec'::uuid,'39b258c9-c3a5-4010-8974-34d7820ff42d'::uuid,'b5627bef-4889-4e99-86ef-ba8e3bf859ec'::uuid,null,'jentra-w5-load-083-20261008','w5_load_20261008'),
 ('load-084','46659684-e93a-466a-84ee-e29eb0a81e26'::uuid,'4b4fe313-f8f2-463d-8c13-34d692441eb4'::uuid,'e7d5f090-38d4-47d1-840b-fbf190021a7d'::uuid,null,'jentra-w5-load-084-20261008','w5_load_20261008'),
 ('load-085','2c7df18e-b86f-4b81-88f9-995d8c667d43'::uuid,'83dc5cf4-d00c-41d5-8abd-72a42ffe12df'::uuid,'f713edf0-dae6-4010-8ec6-c1bb2e73ade7'::uuid,null,'jentra-w5-load-085-20261008','w5_load_20261008'),
 ('load-086','a7dd6641-4f6f-4661-807f-4f83942eb29f'::uuid,'9afa1f37-41f0-4191-8463-468d2eecbb09'::uuid,'579712fa-df9e-4a49-817d-3b0f7fb16ced'::uuid,null,'jentra-w5-load-086-20261008','w5_load_20261008'),
 ('load-087','716fa1c7-234a-4bc4-82cf-65fc59393220'::uuid,'79b75c26-405e-4ff8-8bc1-3bad2bbba146'::uuid,'e19cb137-fc74-4855-8fbb-3147383a052a'::uuid,null,'jentra-w5-load-087-20261008','w5_load_20261008'),
 ('load-088','5564c40b-6cdc-49a7-8a30-a441c71d9496'::uuid,'a904d439-694a-4a71-83dd-1be080d77b75'::uuid,'ed4eb037-ee24-483c-852a-7de8b00cb63e'::uuid,null,'jentra-w5-load-088-20261008','w5_load_20261008'),
 ('load-089','31720aa8-f7e6-41ba-8610-3bf19c07174e'::uuid,'51b263b5-68aa-4cc0-81e8-86e83c4bd0c6'::uuid,'9c5b603e-c997-4a5f-83a1-ba0102b1c281'::uuid,null,'jentra-w5-load-089-20261008','w5_load_20261008'),
 ('load-090','23006860-1b74-4123-88f5-4cc131dcd211'::uuid,'d4df4f9f-cce7-49e5-8c08-8da0cc1ba15e'::uuid,'e509a455-5a54-4b3a-8f79-1dc9b0e57a34'::uuid,null,'jentra-w5-load-090-20261008','w5_load_20261008'),
 ('load-091','62d0e1e2-f8e1-486f-80fe-ed9d456d2e9d'::uuid,'582e5baa-34f1-47ea-893c-580c47b27d9e'::uuid,'7cc25c25-b876-45cd-8811-52956f09f2e7'::uuid,null,'jentra-w5-load-091-20261008','w5_load_20261008'),
 ('load-092','3a3cac6a-48c1-4a18-86ba-ae70d839476a'::uuid,'3b9f73ad-6b3c-4b5b-81bd-eb01afb7ab3f'::uuid,'a9bbc545-2175-4212-827f-88f83c6fa415'::uuid,null,'jentra-w5-load-092-20261008','w5_load_20261008'),
 ('load-093','f11e8c27-2ecf-4bbe-8dbe-4e0b91c16366'::uuid,'3d21147e-64eb-4cdb-835e-137e47e67c8f'::uuid,'3bc34bdd-add4-4acf-83c1-de2da2f2959b'::uuid,null,'jentra-w5-load-093-20261008','w5_load_20261008'),
 ('load-094','4c9857e9-a820-44fc-86bb-4c98011bd4ff'::uuid,'f44c018b-c655-492b-8e40-ad280b67c7bf'::uuid,'93a20283-7aff-49a0-8e0b-f961ceecdc71'::uuid,null,'jentra-w5-load-094-20261008','w5_load_20261008'),
 ('load-095','f8595cd3-c1d8-4a94-8802-9be26e25a8ad'::uuid,'461a33e0-3bbb-4896-8992-18ec52eb54ab'::uuid,'85f91996-e737-4c90-8f22-cdee2f3b356b'::uuid,null,'jentra-w5-load-095-20261008','w5_load_20261008'),
 ('load-096','582a52de-720a-4e37-8e25-a6a721c044dc'::uuid,'aa70db52-9e79-446f-8d3c-b86d79a3c66a'::uuid,'5c012e11-e065-4582-8105-85713bc698e4'::uuid,null,'jentra-w5-load-096-20261008','w5_load_20261008'),
 ('load-097','600a7fc0-93f8-47ae-88f9-d869cadb79a6'::uuid,'61e5955b-eb55-4aa2-8e6f-097fa9f2f56f'::uuid,'cb812bb7-7396-400a-8f37-c4babfdb3f61'::uuid,null,'jentra-w5-load-097-20261008','w5_load_20261008'),
 ('load-098','9860530d-724e-4437-8f7a-e8a071df760b'::uuid,'be6c7cb1-1d02-4ca5-8cd6-32135542d151'::uuid,'fb9fa532-f80d-4bcb-8183-5aa01a705ebb'::uuid,null,'jentra-w5-load-098-20261008','w5_load_20261008'),
 ('load-099','e062529c-8cae-44c2-89d6-840eb959f75c'::uuid,'31336d1a-5a28-44c4-83b0-ac8edecd3af7'::uuid,'e74f0844-a3bd-4ce8-8469-2e99c72703c7'::uuid,null,'jentra-w5-load-099-20261008','w5_load_20261008'),
 ('load-100','c198f0ba-6c21-4ef6-83a3-4d2e53b72729'::uuid,'2f22eaa6-f121-4e8d-827c-ae418f3db73c'::uuid,'06904a1f-2523-42b4-88e7-f98ca4f26777'::uuid,null,'jentra-w5-load-100-20261008','w5_load_20261008'),
 ('load-101','fb4bac71-2544-42c9-8fe9-9f67dd95b71a'::uuid,'3fb3138c-e6c9-42a3-8846-9ac70d89291e'::uuid,'a7291195-6758-485d-81a2-9cb0c49f93ed'::uuid,null,'jentra-w5-load-101-20261008','w5_load_20261008'),
 ('load-102','fad2770c-3506-46c6-849b-023aced551da'::uuid,'66175594-4dfa-4b6e-8f26-bef8f7599e91'::uuid,'70694d53-bda5-48d1-8eaa-25dc100cb67b'::uuid,null,'jentra-w5-load-102-20261008','w5_load_20261008'),
 ('load-103','10e5ca72-8ebf-4487-81a1-40011255c54d'::uuid,'bb298520-95fe-4759-8996-b8cc62233888'::uuid,'1cd9dece-e579-4edd-806c-0de603993b7b'::uuid,null,'jentra-w5-load-103-20261008','w5_load_20261008'),
 ('load-104','777614e4-035a-476a-8af7-b7992442bbf7'::uuid,'33fdb253-ccb3-4f1e-8401-040b2186107f'::uuid,'ed7cb330-90e8-4a95-8d73-6b9571595ea5'::uuid,null,'jentra-w5-load-104-20261008','w5_load_20261008'),
 ('load-105','77e5eb12-3e03-4f82-8c77-6dcee5d2016c'::uuid,'5b0247ea-eadb-46fe-8ea4-7d8043f32004'::uuid,'13b1a4df-cef3-4169-8a60-961dc5b6996b'::uuid,null,'jentra-w5-load-105-20261008','w5_load_20261008'),
 ('load-106','4f69f21c-d126-4fcc-8fcb-ea9c8c9594e4'::uuid,'f5762920-7390-43d1-8f14-5740de5dbcc7'::uuid,'1ed7b1c6-0df9-4738-8b73-ed2b460abeb3'::uuid,null,'jentra-w5-load-106-20261008','w5_load_20261008'),
 ('load-107','a3ff4f0d-4a62-4b39-8774-131d7441199f'::uuid,'1707eec7-7ad8-444f-899e-8211bea19f8a'::uuid,'49725cc7-8830-47bc-85f6-090fbf1fa5d5'::uuid,null,'jentra-w5-load-107-20261008','w5_load_20261008'),
 ('load-108','4451113c-1840-428a-85d9-8e8496798960'::uuid,'560cd129-29d4-42ce-8103-9367c0cf9863'::uuid,'18f1a3d7-30f1-440a-883a-9041fa7aa922'::uuid,null,'jentra-w5-load-108-20261008','w5_load_20261008'),
 ('load-109','ba470464-1bbc-4f0d-81eb-539c611d58e4'::uuid,'2bdcf7d6-6f6c-4d65-8010-6102b3f1cf76'::uuid,'7a2e5bd5-bec1-4fe2-8bc7-c452905547d4'::uuid,null,'jentra-w5-load-109-20261008','w5_load_20261008'),
 ('load-110','22b6d469-0cb8-4e29-87f9-981e2f8e53ca'::uuid,'35cbe07f-aafe-4e06-87d2-0f1d9adbf203'::uuid,'52134aa0-fe35-4e46-878c-2af262786b5a'::uuid,null,'jentra-w5-load-110-20261008','w5_load_20261008'),
 ('load-111','0976ed9e-eca7-4141-8672-d1cb30850d80'::uuid,'d490181c-8222-4b4d-8e56-fbae03a2c8af'::uuid,'01eb1621-7a90-4678-816a-a97aedf2fd93'::uuid,null,'jentra-w5-load-111-20261008','w5_load_20261008'),
 ('load-112','2cbbf3ef-3e57-4721-8721-0bc59ee700b2'::uuid,'a2af7a48-4fa4-4520-8dc5-b481bbd3379c'::uuid,'737950c0-176e-4223-86b3-886e69149ae3'::uuid,null,'jentra-w5-load-112-20261008','w5_load_20261008'),
 ('load-113','826fb914-1ee1-4a8c-8874-7bd287b8f820'::uuid,'9dbe29e4-7b39-4a5d-85e6-53660f4b22d0'::uuid,'8bef958d-7b1a-4591-899e-2e644105224a'::uuid,null,'jentra-w5-load-113-20261008','w5_load_20261008'),
 ('load-114','d312f0e4-4b9a-4f2e-83e9-9cba66716983'::uuid,'3edbc986-b1ea-46d1-83dc-ace165d53e3f'::uuid,'65739c15-36ea-4ac4-8c2d-9abd4d8be567'::uuid,null,'jentra-w5-load-114-20261008','w5_load_20261008'),
 ('load-115','7a933f4a-8d34-42bd-80a1-7b9722263910'::uuid,'610b04ae-55a5-4d86-85a7-8a1386772394'::uuid,'550376a0-192c-4f7e-8607-5238bce06700'::uuid,null,'jentra-w5-load-115-20261008','w5_load_20261008'),
 ('load-116','91ee6c78-0af4-414f-8856-7b855297b211'::uuid,'af7aff56-4ad9-427e-81c6-3460feb9a36b'::uuid,'5e61ad10-40c3-471c-8471-700c50571654'::uuid,null,'jentra-w5-load-116-20261008','w5_load_20261008'),
 ('load-117','380ae35a-410e-4232-8e74-450970526431'::uuid,'b2711408-fb85-49e2-89ce-109da0f4e5e8'::uuid,'659cff70-2f5f-4c94-8be4-0b942f394205'::uuid,null,'jentra-w5-load-117-20261008','w5_load_20261008'),
 ('load-118','81c3e7d6-fa23-4b39-8fb5-4e301efea967'::uuid,'5300e2a9-9b01-4955-8b03-f3cc2f33a334'::uuid,'b970865a-4d8a-40ac-8dfa-e9dfa0355c48'::uuid,null,'jentra-w5-load-118-20261008','w5_load_20261008'),
 ('load-119','fccf8300-f191-49fd-8939-a68872c92064'::uuid,'7e571b01-c627-4fb3-8c63-1c5c3a323c00'::uuid,'51e96193-ec4a-4c2d-8c63-c0e9a75a09de'::uuid,null,'jentra-w5-load-119-20261008','w5_load_20261008'),
 ('load-120','04e40de1-4142-4291-8382-58231e59d074'::uuid,'ef4cc8ee-a209-4d52-817d-38c627bfb157'::uuid,'2e8e5076-71d9-4b09-8049-16fb5a87ed33'::uuid,null,'jentra-w5-load-120-20261008','w5_load_20261008'),
 ('load-121','91ef5d38-35f5-4971-8e7e-0a6639c79ab9'::uuid,'23243b80-d1a6-4776-8298-6196ce56bf29'::uuid,'e3b87f0c-cc9e-4ee6-86e1-7da2c66a419d'::uuid,null,'jentra-w5-load-121-20261008','w5_load_20261008'),
 ('load-122','eddac976-2162-4576-883c-a26f66b14011'::uuid,'5dc2651f-c30f-44ef-8d00-1efa2c12eee5'::uuid,'4b9b653d-d89d-43a0-812c-b1bebbba11df'::uuid,null,'jentra-w5-load-122-20261008','w5_load_20261008'),
 ('load-123','9f7e25a2-7355-49c7-851c-550c58d62871'::uuid,'adf4dd4a-140b-4633-8133-29a23ababa6e'::uuid,'c65ae717-3380-4ed2-8a84-e09cb8d6ab83'::uuid,null,'jentra-w5-load-123-20261008','w5_load_20261008'),
 ('load-124','5e59f791-f5b3-43ca-833d-b636a899779d'::uuid,'270a36a5-2340-4109-841e-55af4fcda703'::uuid,'a3cdcc16-91a0-4c0d-8fd9-5018a535b92b'::uuid,null,'jentra-w5-load-124-20261008','w5_load_20261008'),
 ('load-125','1f39dd56-ec3c-45db-85a2-550963604163'::uuid,'1f54fc0f-d9c3-475f-8d65-04591dca611b'::uuid,'5ae20143-8622-4113-8ad8-01b35586124e'::uuid,null,'jentra-w5-load-125-20261008','w5_load_20261008'),
 ('load-126','ff0fe3a7-cb81-4c46-8209-94e584f24e52'::uuid,'d6ef8c7b-d05b-49d4-84ac-1f1a2149cb13'::uuid,'f64ecab5-0284-4a3c-876d-34050700e6d9'::uuid,null,'jentra-w5-load-126-20261008','w5_load_20261008'),
 ('load-127','eb06333e-2665-48aa-86bc-184b5f560fdd'::uuid,'e5b4bfd1-e7e6-4308-809b-b59fc16f53b8'::uuid,'b044fd12-5e96-4879-8dc4-2f95910b9b54'::uuid,null,'jentra-w5-load-127-20261008','w5_load_20261008'),
 ('load-128','0b044972-ba52-498b-8656-7425b5301a8f'::uuid,'860d20e6-fb69-40be-81ee-003204a3d840'::uuid,'ee2757ed-d30c-452d-8040-d14eb51e4964'::uuid,null,'jentra-w5-load-128-20261008','w5_load_20261008'),
 ('load-129','c9c05286-7034-481d-8402-fe6d339d20c9'::uuid,'4ef41120-1efe-499a-8958-7a14c1f41154'::uuid,'6032d14f-cbd0-4f1b-8ed6-cd490c3a036a'::uuid,null,'jentra-w5-load-129-20261008','w5_load_20261008'),
 ('load-130','13f8f64f-42e8-4b3f-88ae-93f3acc07fe2'::uuid,'6559c7ae-8714-4a6e-8d70-bbd3ec7aff11'::uuid,'c7a2f371-a938-4c4c-8e59-e9f49543b3ed'::uuid,null,'jentra-w5-load-130-20261008','w5_load_20261008'),
 ('load-131','d0f3c15c-f3f5-4de3-8ca2-4539dfe9dd99'::uuid,'ba633fdf-0d5a-4075-8de0-d007afc5d368'::uuid,'983ee579-8ae2-4273-804e-be11d957d1ad'::uuid,null,'jentra-w5-load-131-20261008','w5_load_20261008'),
 ('load-132','0944de64-568b-46a2-88dc-7038872fd572'::uuid,'2a0bfc07-de34-4fdf-880c-2ab073e9e7ac'::uuid,'d92b9f42-ccc8-4c17-81f0-b81d009b4a30'::uuid,null,'jentra-w5-load-132-20261008','w5_load_20261008'),
 ('load-133','b11c5036-914a-4cfb-8cb3-ab2590fc0c42'::uuid,'4460e529-ef19-4346-89a4-816d65ea93d4'::uuid,'93ca8272-a02f-481b-849d-09f19f86af51'::uuid,null,'jentra-w5-load-133-20261008','w5_load_20261008'),
 ('load-134','c330e32d-cc2a-4c01-8436-a9d2f88ddd73'::uuid,'9c6ddc48-8b4b-4f4c-8a6f-073e8491e68c'::uuid,'b9a26668-27a1-4ed1-8c2f-09619935ecb9'::uuid,null,'jentra-w5-load-134-20261008','w5_load_20261008'),
 ('load-135','708fd0e1-e5c0-4bd7-82d2-1b29cc801403'::uuid,'1857719a-1a32-4336-86e3-1b973b7108d9'::uuid,'fac9b0a4-5988-43e9-8cc7-2637669e733c'::uuid,null,'jentra-w5-load-135-20261008','w5_load_20261008'),
 ('load-136','243b116f-310d-4bef-8de5-96b961215dcf'::uuid,'dea2bb35-b893-4af2-8faf-20e94ce2b2c7'::uuid,'a0088c2b-9ae2-4627-8dd4-7f0904fb3463'::uuid,null,'jentra-w5-load-136-20261008','w5_load_20261008'),
 ('load-137','b5dc8da0-8f14-42f7-8f33-c2b937eaf9ba'::uuid,'c83adde6-b523-4fa5-869d-6597a4a5e002'::uuid,'0d59e055-47e9-49f0-82c7-60287cdce894'::uuid,null,'jentra-w5-load-137-20261008','w5_load_20261008'),
 ('load-138','1031845d-82f3-4d18-83a6-107a14698692'::uuid,'b2279fac-26af-4af3-813e-4db08bc1948c'::uuid,'eef50b4e-8541-4abd-8fa4-8ac389b8c7a6'::uuid,null,'jentra-w5-load-138-20261008','w5_load_20261008'),
 ('load-139','0f39a6aa-53ad-4f71-858b-8586cf65be38'::uuid,'d1f81b03-169d-4d28-8eec-9d14f7e9eb91'::uuid,'4ed70174-570c-417c-8840-de5133f5b40c'::uuid,null,'jentra-w5-load-139-20261008','w5_load_20261008'),
 ('load-140','87d64230-c14e-42a9-8696-e527a1d967e8'::uuid,'6b27acf6-ffb0-4842-866a-886b4decb2f2'::uuid,'3f52204b-76fb-4317-8975-aacdeaec512e'::uuid,null,'jentra-w5-load-140-20261008','w5_load_20261008'),
 ('load-141','3b5060a6-2d14-4fab-83a0-ca9e9acd362c'::uuid,'a3f18e8a-b4cf-46a1-8020-e856377966cd'::uuid,'59f9b153-06d3-4960-8a33-c4c7f4f1e366'::uuid,null,'jentra-w5-load-141-20261008','w5_load_20261008'),
 ('load-142','61ddaffe-9a58-4190-8c56-b5ee939de519'::uuid,'b1a00319-fe20-474e-8caa-08eda40a53d0'::uuid,'db213540-4c7c-411c-8588-b6c169157810'::uuid,null,'jentra-w5-load-142-20261008','w5_load_20261008'),
 ('load-143','c5918fce-dace-4b51-82d8-09689e1a201f'::uuid,'2a9dd374-fb61-4654-8dee-a572753263df'::uuid,'e03ee3dd-b1af-4270-8446-8ad00f9bd2fe'::uuid,null,'jentra-w5-load-143-20261008','w5_load_20261008'),
 ('load-144','9d5e62bf-6144-4e77-84bd-fb7807de0670'::uuid,'553c3096-314d-4f0e-83da-51892077f423'::uuid,'94bd5862-4dc7-48ae-81d5-9271231bdfef'::uuid,null,'jentra-w5-load-144-20261008','w5_load_20261008'),
 ('load-145','875cbbdb-d6d3-46ab-8300-e09a97f7e833'::uuid,'5a2d33f0-cebf-4063-8bbf-a7ac1d86e695'::uuid,'93ce4522-dedf-4553-8975-12959910654a'::uuid,null,'jentra-w5-load-145-20261008','w5_load_20261008'),
 ('load-146','90df5765-96c2-48df-85f8-dfd05517d516'::uuid,'57bf8722-bfe9-4d7d-8a96-4b801aa1b569'::uuid,'a1b8b16c-0fd7-44ea-82f5-49816752fdce'::uuid,null,'jentra-w5-load-146-20261008','w5_load_20261008'),
 ('load-147','095b8470-41b3-4c1a-874a-6ea3ea003926'::uuid,'a1579897-8077-41f9-82cb-0b05199bc57c'::uuid,'31910b69-39bf-40aa-8040-b4dab923785f'::uuid,null,'jentra-w5-load-147-20261008','w5_load_20261008'),
 ('load-148','751c8246-fa6d-40bd-814b-57892415c294'::uuid,'2a225a1e-9728-4917-8d19-526231207ffa'::uuid,'7ee67512-6178-44a4-8f75-1530a54ad07d'::uuid,null,'jentra-w5-load-148-20261008','w5_load_20261008'),
 ('load-149','cb4a8652-29b1-46cb-80fd-a06881459826'::uuid,'72e356d8-d0df-4068-8b97-83095aceaf33'::uuid,'6eb42ff1-a93e-486c-8403-0fb3a5189d93'::uuid,null,'jentra-w5-load-149-20261008','w5_load_20261008'),
 ('load-150','b14eaeee-1377-48ea-8747-34327b61e755'::uuid,'8f43e59c-88c9-4f87-8852-1c9c1b2e107f'::uuid,'5d8bd8e6-f71b-46f5-8373-a13fdb4d5546'::uuid,null,'jentra-w5-load-150-20261008','w5_load_20261008'),
 ('load-151','7fc526da-33d9-451f-8bbd-7504710d30f8'::uuid,'1d2a3ada-e95e-4010-857d-27b722930575'::uuid,'a568433a-6ebd-4af4-82c5-c4cf53c8576c'::uuid,null,'jentra-w5-load-151-20261008','w5_load_20261008'),
 ('load-152','a312ad93-580f-4057-8ca9-6a8e4a61a8b3'::uuid,'11779856-0320-4927-8091-71af9cfb44eb'::uuid,'430573b8-549a-4688-8017-7dee17083932'::uuid,null,'jentra-w5-load-152-20261008','w5_load_20261008'),
 ('load-153','7d1f2a88-4c49-4b5e-8c0c-d2f007eb639f'::uuid,'e40c64b1-bc29-4ee9-869d-3af2cb395c7a'::uuid,'a3114ba7-9b40-4b34-83f6-5846ed0070c4'::uuid,null,'jentra-w5-load-153-20261008','w5_load_20261008'),
 ('load-154','5573f0e5-d69d-4316-8b80-debd9e5f6dd2'::uuid,'06f51a14-0988-4905-8139-2d6ba6afb0c9'::uuid,'aaf463e5-73f6-4fcc-8c28-625f9fb198bb'::uuid,null,'jentra-w5-load-154-20261008','w5_load_20261008'),
 ('load-155','869f42ee-7af1-446e-8627-6345604d8440'::uuid,'f6927642-0403-4f5a-8d52-971bcb2b45e6'::uuid,'2dc7e333-2239-4cd8-812e-671ea81ee970'::uuid,null,'jentra-w5-load-155-20261008','w5_load_20261008'),
 ('load-156','ab0d2faa-7e15-401b-850e-f71004345841'::uuid,'9d4723f8-7457-466b-8acc-c40d013571ad'::uuid,'fc5b14fb-9490-467c-8ada-3f7b8656963f'::uuid,null,'jentra-w5-load-156-20261008','w5_load_20261008'),
 ('load-157','965e42bc-1c5b-42ab-8f48-4f33c956ddce'::uuid,'2a1cfe19-b756-47cf-89a8-8f4b6976a5aa'::uuid,'ab9a47d2-ee7a-47d3-89c6-e5fc7650763f'::uuid,null,'jentra-w5-load-157-20261008','w5_load_20261008'),
 ('load-158','e92e9a60-a192-40b2-8426-db6e54fb635a'::uuid,'ea8dc40b-0855-4d43-8e40-8230bad46658'::uuid,'09e70cf3-3e6d-484d-80bc-46be0ec94354'::uuid,null,'jentra-w5-load-158-20261008','w5_load_20261008'),
 ('load-159','6b3f339b-8098-41b7-8cf7-5a847f7eda79'::uuid,'5e2c44bb-60d3-4b46-8e68-e184c316bcdc'::uuid,'3174d23f-0bf6-4f0c-8bc9-944620267178'::uuid,null,'jentra-w5-load-159-20261008','w5_load_20261008'),
 ('load-160','b91bc9d5-e7b3-4b44-842e-35c2a25e16b7'::uuid,'a18e20bc-0f90-48fc-8d80-3405a55f9623'::uuid,'54e9c61f-025e-4cb0-8efe-47a09c64b380'::uuid,null,'jentra-w5-load-160-20261008','w5_load_20261008'),
 ('load-161','574f28b6-7b06-4cd7-8131-6eedfc3b0f71'::uuid,'0f7e1f42-5fc2-47e1-8f6a-620cc41fae24'::uuid,'30dffddd-53cd-4d7e-8188-788e65031b37'::uuid,null,'jentra-w5-load-161-20261008','w5_load_20261008'),
 ('load-162','f658ca81-0672-4395-8f18-e4d624708efb'::uuid,'db54a4b1-d387-4591-893a-a548c29817b2'::uuid,'1b8cc119-74e2-441e-862a-87ad40f2e70a'::uuid,null,'jentra-w5-load-162-20261008','w5_load_20261008'),
 ('load-163','c599a5ea-68b2-49e6-8b60-9f7f5cc86b90'::uuid,'1a66d6a4-c7b4-472a-8d13-bdf501dfffcd'::uuid,'b1c1c447-b256-44ee-8fc5-4c4996c86221'::uuid,null,'jentra-w5-load-163-20261008','w5_load_20261008'),
 ('load-164','03463cf6-b1a6-4767-8fe2-ab7616389b49'::uuid,'f8d03c63-b4b5-4a10-8567-f8d68db82bde'::uuid,'bb24b3f0-5192-41ec-8fc7-11966d28ec49'::uuid,null,'jentra-w5-load-164-20261008','w5_load_20261008'),
 ('load-165','f1d9a6d1-c247-4e1f-8198-4d0513e00e1a'::uuid,'e8cd8d72-ce18-40bc-8e62-288d51438760'::uuid,'fba893af-3bc9-4f6b-8ae8-acc1cc2f770d'::uuid,null,'jentra-w5-load-165-20261008','w5_load_20261008'),
 ('load-166','fcad99d9-e9eb-45af-802a-4a190810e1d6'::uuid,'7e982959-ec79-4b21-83ad-cdc807fae28b'::uuid,'8c2c0e65-1aa7-4af4-885f-7cfee5f62678'::uuid,null,'jentra-w5-load-166-20261008','w5_load_20261008'),
 ('load-167','aa911f69-c9a5-4bd8-8079-ffa07838e172'::uuid,'e3e889bd-38a3-472b-8191-1e8f09e409a6'::uuid,'e7c86aad-6c70-4294-82bd-3395ed5be1c0'::uuid,null,'jentra-w5-load-167-20261008','w5_load_20261008'),
 ('load-168','b011abcd-df39-4cb1-86d5-daca86864d0c'::uuid,'3ce3a27f-93d9-404e-85db-76c0d26886de'::uuid,'d75cc1e8-62e7-4296-83fc-9ae039fdf102'::uuid,null,'jentra-w5-load-168-20261008','w5_load_20261008'),
 ('load-169','3ab3ac90-29f9-40dc-8a58-e6c2b219eb0c'::uuid,'8d1b50b4-8a3c-4b90-812f-321e2b2cd786'::uuid,'8757e9f2-33b0-4a1f-8ec2-f3d282952577'::uuid,null,'jentra-w5-load-169-20261008','w5_load_20261008'),
 ('load-170','e1f32113-02a6-46be-8feb-d61078ce43df'::uuid,'d47fc6cc-7632-4ffe-8760-d1f86f7939cd'::uuid,'a08c22f7-8a18-40ca-8b7b-0a6145fe1118'::uuid,null,'jentra-w5-load-170-20261008','w5_load_20261008'),
 ('load-171','b57cc7d9-f9f0-47fc-8895-9a636d762ec8'::uuid,'79a1b533-7a48-4c40-8daf-872bd7f7d0d4'::uuid,'535629bb-1c4b-41a7-81be-054004d71f5b'::uuid,null,'jentra-w5-load-171-20261008','w5_load_20261008'),
 ('load-172','4a5238e5-1e54-4e2c-88f6-b8a8672cb597'::uuid,'b5cad0e0-a1eb-4e41-87a7-ffe99d59acd6'::uuid,'636ceeea-310c-4478-8757-66ea725297d9'::uuid,null,'jentra-w5-load-172-20261008','w5_load_20261008'),
 ('load-173','20406411-3299-408d-8651-b820e3523d91'::uuid,'d7259898-bab0-434c-8264-d293da724b00'::uuid,'6add13c4-9ee6-4790-81c6-e9c34c7bf701'::uuid,null,'jentra-w5-load-173-20261008','w5_load_20261008'),
 ('load-174','1f8114b2-8f37-4455-881a-5b60a4334460'::uuid,'db84f0dd-e54c-49e9-8169-622f258fff58'::uuid,'629be656-feb4-4c45-8995-3c7cfff60bf7'::uuid,null,'jentra-w5-load-174-20261008','w5_load_20261008'),
 ('load-175','f267b242-47f8-4cbf-85e7-1611c21e0796'::uuid,'3bb68e7a-9c5c-428d-8fe8-b96b4c5ea9d6'::uuid,'63f75913-bddc-439a-8421-98b4afd527ae'::uuid,null,'jentra-w5-load-175-20261008','w5_load_20261008'),
 ('load-176','57c682b4-9e43-4376-8db8-1441c4e80494'::uuid,'11871cfe-910d-4361-8db4-518527802b36'::uuid,'964f89b3-314e-4f7b-8a70-1fcdc327e3aa'::uuid,null,'jentra-w5-load-176-20261008','w5_load_20261008'),
 ('load-177','520ec1d1-ac60-489d-864f-154c74809505'::uuid,'f77e7e9c-e1b1-42d4-8026-63a60fecb2de'::uuid,'7554988d-ad3c-42c3-82ed-92d9fb475122'::uuid,null,'jentra-w5-load-177-20261008','w5_load_20261008'),
 ('load-178','f79e7dce-d984-47ce-89b3-a8f46900f0b7'::uuid,'61fcf2a1-3806-43df-8122-d0f5ee5ffda0'::uuid,'dfe293f2-fde4-4e94-8e15-1d6fc1c3fc66'::uuid,null,'jentra-w5-load-178-20261008','w5_load_20261008'),
 ('load-179','bbcacf39-4e82-47c5-8944-4ae0d0120dfb'::uuid,'6561ef06-b302-4681-8d13-8718164c2e5a'::uuid,'1a9a3e8c-ea5d-4f9b-8da3-de0533404327'::uuid,null,'jentra-w5-load-179-20261008','w5_load_20261008'),
 ('load-180','dc30bb28-7dcd-4139-867d-84dc9e60d5e7'::uuid,'2ec89f4f-0c5b-4c27-8a98-136804ed7874'::uuid,'3c2f39e4-ed73-4d4f-8d3d-d98536597ec7'::uuid,null,'jentra-w5-load-180-20261008','w5_load_20261008'),
 ('load-181','e7516883-c919-4177-832a-e104ff13d67d'::uuid,'a8a2c871-12f3-4f0f-8344-1ee485655130'::uuid,'9397f178-38fb-42ec-8b8e-91851151dc04'::uuid,null,'jentra-w5-load-181-20261008','w5_load_20261008'),
 ('load-182','56ae5a66-783a-43a1-8f8b-7ef7e7aac6a8'::uuid,'a45950a7-24db-4c98-8306-8f64fae7d44e'::uuid,'5a200910-a7d5-433c-8157-35f0402d6140'::uuid,null,'jentra-w5-load-182-20261008','w5_load_20261008'),
 ('load-183','2ec43565-724c-4c36-8754-3b36513d0f25'::uuid,'f76b79a0-83ad-4bfe-8a77-476390bee181'::uuid,'5e3305dd-090f-4e32-8b68-0a68b2aeb23b'::uuid,null,'jentra-w5-load-183-20261008','w5_load_20261008'),
 ('load-184','8dce5ae1-b8c6-4737-8091-9fbc2e788e87'::uuid,'94fc3fb2-9580-439e-85e6-729535532720'::uuid,'27acbdc0-b4fd-49c9-8c43-4df898672ac9'::uuid,null,'jentra-w5-load-184-20261008','w5_load_20261008'),
 ('load-185','cc59f899-3b91-4fee-8b2c-b9dcdfaa2b7e'::uuid,'3f3ac0e7-e9f3-49aa-870f-20e8c713a105'::uuid,'4a8f2a33-0924-4042-8c3d-6c6ef91c33eb'::uuid,null,'jentra-w5-load-185-20261008','w5_load_20261008'),
 ('load-186','4130a1d7-4ac4-49b4-85e8-23384deeeaf2'::uuid,'17257eb1-9a6c-42af-8f4b-7a31de35f442'::uuid,'eca1ee2d-fa02-4994-884f-d1257a447ad4'::uuid,null,'jentra-w5-load-186-20261008','w5_load_20261008'),
 ('load-187','d63a542a-9106-4c4a-8874-9f2b4070d34a'::uuid,'d4198559-1234-48b9-8988-f8b039bb7a64'::uuid,'423a2278-3b14-4edc-8d89-ff8f1f2fd493'::uuid,null,'jentra-w5-load-187-20261008','w5_load_20261008'),
 ('load-188','1cbb8e4a-b351-448e-8d7f-df9595607e3a'::uuid,'b630739d-8636-4459-88f8-27c5818000d9'::uuid,'f42fc5ae-f16a-4287-8e85-b3dcde754b06'::uuid,null,'jentra-w5-load-188-20261008','w5_load_20261008'),
 ('load-189','979e03c6-e26f-4f4c-85ee-e84fa962e41a'::uuid,'6e6a4f62-02a2-468c-857a-156b334bcae2'::uuid,'73b103f8-02ac-4652-8bfa-a03a74802f47'::uuid,null,'jentra-w5-load-189-20261008','w5_load_20261008'),
 ('load-190','52bea53c-c251-4f85-89cd-9f451fbbe5f7'::uuid,'7331c6c1-5bac-43ec-8ed5-e135524ac94a'::uuid,'dbe2e1f6-0a42-4846-8b02-686d68119c75'::uuid,null,'jentra-w5-load-190-20261008','w5_load_20261008'),
 ('load-191','97249d9c-0ae3-48e0-8068-61755c80e741'::uuid,'058a58b2-e783-4f65-86f8-5e96a7804335'::uuid,'fe641378-7c12-4abe-84f8-14407ef83c0a'::uuid,null,'jentra-w5-load-191-20261008','w5_load_20261008'),
 ('load-192','334c9e65-cb3c-4b69-8ef8-f57f14e01275'::uuid,'d8a08579-196f-4047-8819-290694b7ee03'::uuid,'fdeeb2a4-fdd9-4510-8060-1256ed7795c2'::uuid,null,'jentra-w5-load-192-20261008','w5_load_20261008'),
 ('load-193','be812378-9e6a-476c-81bc-11e4249bce75'::uuid,'ffbb14b8-0b44-43e6-8872-41cabea39deb'::uuid,'33d480a8-c7dd-4da8-8edd-bf7a469c6f7e'::uuid,null,'jentra-w5-load-193-20261008','w5_load_20261008'),
 ('load-194','e0cc3675-1ecb-4039-81c6-8e9c42c87d84'::uuid,'913f5bf6-9886-4d04-83d8-f089ccc1f09b'::uuid,'1fb40230-0c5e-4d97-8dbe-213cd72f0f70'::uuid,null,'jentra-w5-load-194-20261008','w5_load_20261008'),
 ('load-195','b079257b-aa48-4b76-8f85-ae4d14d3aebc'::uuid,'2ececc3f-0fea-42a9-8b1e-18a9b67db130'::uuid,'621b9653-51cc-481d-8cde-ba976e3527f7'::uuid,null,'jentra-w5-load-195-20261008','w5_load_20261008'),
 ('load-196','edbf63c2-3429-491b-8b3f-a1d293a59184'::uuid,'33f5480a-b038-4d3e-8363-be5121a9de08'::uuid,'3573dbe6-d7f6-4d96-8d1f-551d0de29817'::uuid,null,'jentra-w5-load-196-20261008','w5_load_20261008'),
 ('load-197','07db23a0-c5c1-4d94-8479-1a2dbfb1efcf'::uuid,'44b880de-8991-4619-8db8-648f18ecf9cc'::uuid,'9ac9491f-3c23-4e97-8515-58c3f84a1e5a'::uuid,null,'jentra-w5-load-197-20261008','w5_load_20261008'),
 ('load-198','9ba4f543-e553-4e84-869a-751e73ae955c'::uuid,'1b001516-53ac-44d4-8567-59bfa57ba75c'::uuid,'8a392112-f016-43f3-8274-0d7bb64306fd'::uuid,null,'jentra-w5-load-198-20261008','w5_load_20261008'),
 ('load-199','38d20e62-4ba5-49d7-8ae2-9371d0274302'::uuid,'aeef0c97-970e-4802-82b7-4c6664f85291'::uuid,'96f18c72-e11d-4827-8d03-1ce47b73ebca'::uuid,null,'jentra-w5-load-199-20261008','w5_load_20261008'),
 ('load-200','df67c8c0-2a4a-4779-8825-8a8dbed4b2c1'::uuid,'284fc2b0-5d3d-4f7a-8f31-8a88999c9daf'::uuid,'42f4a4b3-a6ec-4121-86ec-a5e2d0bcce52'::uuid,null,'jentra-w5-load-200-20261008','w5_load_20261008'),
 ('load-201','88a9ed4d-7f53-4a51-84dc-d33f0085f840'::uuid,'a111ef37-41fa-4636-87c0-cb6391388abe'::uuid,'b2bd3bb8-a5b1-4752-85c5-23235efc2311'::uuid,null,'jentra-w5-load-201-20261008','w5_load_20261008'),
 ('load-202','138ee2fb-4cde-4a2b-8fc9-babe378aa32c'::uuid,'d5223b95-0724-49f1-828d-3cd1c22a322f'::uuid,'b65cc4ab-5484-4f81-888f-6314e58ae5fb'::uuid,null,'jentra-w5-load-202-20261008','w5_load_20261008'),
 ('load-203','eb68b170-17d0-47e4-81c8-60534ad708ab'::uuid,'0935f1a3-724b-4857-8f6e-f4107f2032f9'::uuid,'5766a627-b411-46aa-873b-a9fcdbc68337'::uuid,null,'jentra-w5-load-203-20261008','w5_load_20261008'),
 ('load-204','cbc3b6e1-83f3-40dd-8d94-d1450fa9780b'::uuid,'26d6359b-9189-4c14-85a3-da6951cd3686'::uuid,'971d5cd1-702a-450b-8ca1-ed4c99fe9f5b'::uuid,null,'jentra-w5-load-204-20261008','w5_load_20261008'),
 ('load-205','8b4028e5-0efd-4ba5-8da3-44a6722f27f2'::uuid,'1bc9553b-0117-4d1b-8d8e-b3159b162244'::uuid,'3e3d5b9a-49e2-4de2-8582-681293601384'::uuid,null,'jentra-w5-load-205-20261008','w5_load_20261008'),
 ('load-206','b0fe7a58-527e-482a-8212-d5875a0c80aa'::uuid,'652c47aa-26cf-4945-8967-fdb36430d6c5'::uuid,'fac5eb57-3cf6-4294-8072-cafd045f4995'::uuid,null,'jentra-w5-load-206-20261008','w5_load_20261008'),
 ('load-207','fb9ce446-ec52-4304-8180-1bf0d0a7e5f3'::uuid,'5a4724d1-bf15-4ce6-8fb4-6c76cd23a641'::uuid,'3fa31483-d60d-4296-8216-1b2b3bbfbc99'::uuid,null,'jentra-w5-load-207-20261008','w5_load_20261008'),
 ('load-208','b2bd4543-31de-4137-845a-9bfccd4a1593'::uuid,'fa11eadb-c3e5-4ff4-8075-3f9a853697c8'::uuid,'53771fb7-326a-439c-80a2-e117505406ad'::uuid,null,'jentra-w5-load-208-20261008','w5_load_20261008'),
 ('load-209','66a00f12-16dc-4106-8b52-512f38244a95'::uuid,'d22111a9-3f8b-4e5e-88b7-db2ea1deb9f8'::uuid,'916f80df-5578-4a9c-83c4-cac98c0518ca'::uuid,null,'jentra-w5-load-209-20261008','w5_load_20261008'),
 ('load-210','f7b376da-cf4e-481b-8a39-766c48c3c921'::uuid,'35b1dbbd-07be-4a8b-8381-04a7df3ee37a'::uuid,'81b256a4-cea8-41a5-8b28-b94198d84e2d'::uuid,null,'jentra-w5-load-210-20261008','w5_load_20261008'),
 ('load-211','7dae3ee9-7418-4b3e-84bd-0d048166a870'::uuid,'a1b78930-079a-4f62-8bdd-0ee87ab38357'::uuid,'0d6de719-f641-4459-8cb3-14e46b62b384'::uuid,null,'jentra-w5-load-211-20261008','w5_load_20261008'),
 ('load-212','f9048f32-2e36-43d1-8ac3-3ddfb672a829'::uuid,'380b2956-ae8c-454b-8051-824ba6c1a5b2'::uuid,'08fb8d74-f15c-4d2e-8ddd-f3bdddb913a9'::uuid,null,'jentra-w5-load-212-20261008','w5_load_20261008'),
 ('load-213','d490a20b-27ee-4da7-886a-9af5f5cc2a14'::uuid,'293e805a-bb31-4ec8-8e11-529c608b6535'::uuid,'6988597a-fb31-4f9e-8b17-ef5657c3969d'::uuid,null,'jentra-w5-load-213-20261008','w5_load_20261008'),
 ('load-214','53dc0ed5-0c6b-4fab-88aa-9d834a242ad8'::uuid,'eb5ba478-84a9-40e1-8488-d1863510ad76'::uuid,'8b6f78cd-bccc-428f-84c5-80ea5c3b655d'::uuid,null,'jentra-w5-load-214-20261008','w5_load_20261008'),
 ('load-215','e62c8a90-c9ad-4cae-87dd-a4f90cc1f7d1'::uuid,'cce77700-fc9f-4d5d-8e20-d187a6ec3957'::uuid,'c4a11e7a-fd64-4341-89de-50025b933fe0'::uuid,null,'jentra-w5-load-215-20261008','w5_load_20261008'),
 ('load-216','08498aa4-985c-431e-8714-3d9d48683f93'::uuid,'85f1a24c-bd2f-4c54-83eb-c9a37088b144'::uuid,'3d491d2d-f8a7-466e-8731-2d10564603bf'::uuid,null,'jentra-w5-load-216-20261008','w5_load_20261008'),
 ('load-217','8236691e-8917-40a7-884f-7183a7f9ee9a'::uuid,'b0206970-0a1e-488d-804a-1ecbe7357ee9'::uuid,'81a6c4db-e952-4ffb-8ef9-47ae9907a876'::uuid,null,'jentra-w5-load-217-20261008','w5_load_20261008'),
 ('load-218','62d5c6ca-573b-484e-8798-b464a5512c76'::uuid,'5cbd7e32-e954-4280-8ab4-c18a9ac8e2fc'::uuid,'88362a8b-b791-4219-8380-f06b04ea43ec'::uuid,null,'jentra-w5-load-218-20261008','w5_load_20261008'),
 ('load-219','df374532-1fe2-4d13-8321-b7a237579b70'::uuid,'c2da5e08-6a90-4efa-8a54-6f80a985f6ec'::uuid,'ffece4b8-e934-4d38-8985-c942308b50c7'::uuid,null,'jentra-w5-load-219-20261008','w5_load_20261008'),
 ('load-220','6b6ab6f8-574d-4eda-8f47-749d0eb05ccf'::uuid,'5e770389-1aec-492d-8eca-e1eff70e3c09'::uuid,'2949c3ac-7375-4e0b-8a25-bea28e86a6ae'::uuid,null,'jentra-w5-load-220-20261008','w5_load_20261008'),
 ('load-221','5b455e63-3afb-41d5-88a7-ca7208ffcd87'::uuid,'9dc0e374-1ae0-40ce-84ef-5e1138177026'::uuid,'cc5c0d00-efd6-4eb4-8299-e092db8c1933'::uuid,null,'jentra-w5-load-221-20261008','w5_load_20261008'),
 ('load-222','b6a46f1f-a147-471d-8060-8e3348ac24da'::uuid,'6d9ca202-1170-4434-8714-4e73ae1daf10'::uuid,'542dc13f-f5df-4e87-8fc3-8d4b4b040d34'::uuid,null,'jentra-w5-load-222-20261008','w5_load_20261008'),
 ('load-223','b0a8f019-8e5f-411e-8808-bcf68e04139e'::uuid,'09523651-3f74-4212-8f5f-b56444905c70'::uuid,'a6b931e8-1699-4488-86fb-48e16305bd19'::uuid,null,'jentra-w5-load-223-20261008','w5_load_20261008'),
 ('load-224','9baa4e7f-3255-4b6e-8fff-3623ca71e919'::uuid,'29ef9827-b04d-4998-8a00-6d4ee94012e3'::uuid,'e5e5c019-cfbc-4446-82b6-0c9d2dc878f2'::uuid,null,'jentra-w5-load-224-20261008','w5_load_20261008'),
 ('load-225','523fa64d-33f7-4642-8d0f-93f8b26a4be7'::uuid,'49b7e72b-d250-45e4-8425-df31acd51c72'::uuid,'f509d902-c796-4c26-847e-35209bb3604e'::uuid,null,'jentra-w5-load-225-20261008','w5_load_20261008'),
 ('load-226','4b2dc450-503e-4a77-8294-d1d6dd57e528'::uuid,'b637fd2d-2768-4753-86c4-4b77c360a450'::uuid,'29602abb-5a64-4eb2-8831-5417e19c3637'::uuid,null,'jentra-w5-load-226-20261008','w5_load_20261008'),
 ('load-227','f77e9f9d-5b96-4ca7-8e31-311bb6b46b53'::uuid,'651cd1f6-da20-4b88-8164-59801fe08233'::uuid,'cd4ab274-e246-47ab-8550-4080527ed2d2'::uuid,null,'jentra-w5-load-227-20261008','w5_load_20261008'),
 ('load-228','8e65fdd2-2dac-493e-833c-6d2d36abf026'::uuid,'bf1b8d07-09f8-4d07-8185-470ea9e37442'::uuid,'31bc5ad9-3b5a-459c-8d06-759e850bf88a'::uuid,null,'jentra-w5-load-228-20261008','w5_load_20261008'),
 ('load-229','262348fb-8dec-4b38-8c21-cb86a6ed7137'::uuid,'4a0a8d53-ba82-4ea7-8039-fcdbed109f75'::uuid,'4aa97346-cd20-4c72-8f94-d1deca43e19a'::uuid,null,'jentra-w5-load-229-20261008','w5_load_20261008'),
 ('load-230','f4e55f6d-33e5-44d8-8736-5420e54371e0'::uuid,'22eab805-1103-46d5-88a6-a7b12c8ab66a'::uuid,'aa07ae82-4599-4c62-8872-c8a8885cfb23'::uuid,null,'jentra-w5-load-230-20261008','w5_load_20261008'),
 ('load-231','330811e6-f0b4-40e1-8f8a-8755ddc253b3'::uuid,'327deb41-1a56-47fa-8ff6-7608f7289c88'::uuid,'5569f361-67b8-414f-8fb6-692efb20c922'::uuid,null,'jentra-w5-load-231-20261008','w5_load_20261008'),
 ('load-232','2b9d155b-8c72-4342-80cd-b2ff4c8a0eed'::uuid,'f8a8aca9-c561-4b57-899f-441cd447ace8'::uuid,'9d7bcbbb-01e7-4216-881e-130f72682f79'::uuid,null,'jentra-w5-load-232-20261008','w5_load_20261008'),
 ('load-233','3b286330-2698-4b02-876c-c4ae27c83a4a'::uuid,'d0565e18-8298-4a02-8c8d-fcb17ed5b152'::uuid,'d5714d3d-4516-48c5-89be-caa7de82edbd'::uuid,null,'jentra-w5-load-233-20261008','w5_load_20261008'),
 ('load-234','f5223de2-f52f-4627-8d4d-e1e31bdadef7'::uuid,'d77ac3ca-3b1e-4cba-8a9c-5d26aec3dc45'::uuid,'733608fd-5bd6-4847-8e48-b47805b427f6'::uuid,null,'jentra-w5-load-234-20261008','w5_load_20261008'),
 ('load-235','76e23e75-61f9-4e6f-8869-5d0feb65be84'::uuid,'4ae6a051-14d1-4bcb-8793-699c9fd47dd8'::uuid,'4b107ad2-48b2-420e-8be7-a80a4a6ffc5e'::uuid,null,'jentra-w5-load-235-20261008','w5_load_20261008'),
 ('load-236','640d8ecc-c46c-4dd9-86f7-d3d980fadfe4'::uuid,'6c2e9f2a-99dc-4de9-80fe-479b58022a27'::uuid,'48686265-68c5-4c26-817c-39f38355c13a'::uuid,null,'jentra-w5-load-236-20261008','w5_load_20261008'),
 ('load-237','4dd0fc62-765d-4c46-8bfe-2ed2e24efdcb'::uuid,'3af2b3bc-1e53-4cb9-8669-2fa4ac0ad57b'::uuid,'40938625-d948-429c-8c71-8358dd100e31'::uuid,null,'jentra-w5-load-237-20261008','w5_load_20261008'),
 ('load-238','ae7f6746-1c35-4696-8679-c49e38f05e45'::uuid,'708e0d25-c801-4a87-8860-427c9a8d3b90'::uuid,'ec3f6b4b-5893-4449-8c85-0d7888e590f1'::uuid,null,'jentra-w5-load-238-20261008','w5_load_20261008'),
 ('load-239','4b30616c-2425-4a93-8d84-1ea0322b3bef'::uuid,'4568390c-b151-4301-8e9d-6e59e6e78375'::uuid,'4b460352-c337-497c-8643-28dbe547447b'::uuid,null,'jentra-w5-load-239-20261008','w5_load_20261008'),
 ('load-240','0fc63003-0360-4795-8e25-62b0b2cf8474'::uuid,'6c237f0f-4e22-4bed-843e-2960230ebfbf'::uuid,'940b5cba-6016-40ac-825e-a3721e82d72c'::uuid,null,'jentra-w5-load-240-20261008','w5_load_20261008'),
 ('load-241','d6d90e66-3c5b-4187-8061-0f4473cee4ae'::uuid,'67a11769-c4ca-41ae-858e-a0ee2a49b724'::uuid,'f79f9dc4-a73a-40c7-8bf4-3e9a70a64d49'::uuid,null,'jentra-w5-load-241-20261008','w5_load_20261008'),
 ('load-242','4226c892-c4cc-45d6-8598-049de2590112'::uuid,'3421322c-cbe0-461c-8fbd-f9a6ccdffcf0'::uuid,'cc0445fb-f69e-4f98-8d79-359554a0955f'::uuid,null,'jentra-w5-load-242-20261008','w5_load_20261008'),
 ('load-243','edfc1451-3736-496e-819d-565a65234d6c'::uuid,'8ef59252-e97f-4198-86b1-5e8f4da4fc7e'::uuid,'44cca35d-1098-4432-8b27-e10771cafa4f'::uuid,null,'jentra-w5-load-243-20261008','w5_load_20261008'),
 ('load-244','29f4da48-606f-49f6-8355-ba3bd3a5d2a9'::uuid,'44b2a925-f65a-48b3-8ece-a6cda3b1a3e2'::uuid,'09f50be4-69e1-4bca-8bba-32e087021f1b'::uuid,null,'jentra-w5-load-244-20261008','w5_load_20261008'),
 ('load-245','60b86217-f578-4777-812b-22257addeb81'::uuid,'72b60acd-0cb5-4460-8e8d-0b55444e3fa5'::uuid,'c85352b8-1442-445e-817d-343fb335d9e0'::uuid,null,'jentra-w5-load-245-20261008','w5_load_20261008'),
 ('load-246','931356c4-935a-4eaf-86e2-de9f82fe380d'::uuid,'c742a810-85d3-4f95-8063-1a0a032da352'::uuid,'b791c73d-8718-4c58-8f68-b60de8916651'::uuid,null,'jentra-w5-load-246-20261008','w5_load_20261008'),
 ('load-247','81de924f-17f0-4cb2-82c6-5168eb3d5090'::uuid,'57616717-fd21-412c-8c64-fcf87ed9720a'::uuid,'852e8c32-402a-4711-8dad-0737948fb586'::uuid,null,'jentra-w5-load-247-20261008','w5_load_20261008'),
 ('load-248','d6c7dd18-6056-41d6-8bc8-0f612785bde5'::uuid,'11963bf8-f524-4700-8930-f993ac242423'::uuid,'dbe3b424-41bb-46b8-86c8-e32c22c465ab'::uuid,null,'jentra-w5-load-248-20261008','w5_load_20261008'),
 ('load-249','ffcd7cc8-e694-474d-8458-46a6fbbb660d'::uuid,'3e880a2d-122b-4973-82de-c9abdbda2eed'::uuid,'7b957e46-89af-4d0c-8b7c-804ed44f75c4'::uuid,null,'jentra-w5-load-249-20261008','w5_load_20261008'),
 ('load-250','20bd1cce-69d4-4378-856b-87b942515040'::uuid,'3680619e-c334-4cf3-8be5-122dc3c766ad'::uuid,'d69939e5-7b1f-4351-8700-efe82377c2b9'::uuid,null,'jentra-w5-load-250-20261008','w5_load_20261008'),
 ('load-251','f1b8df22-5a61-44bb-8df6-14ed3945b1db'::uuid,'bb63310a-6eb5-466f-81c1-20f8d9010b00'::uuid,'ef1f0984-73f9-4c12-8a65-275800493c8d'::uuid,null,'jentra-w5-load-251-20261008','w5_load_20261008'),
 ('load-252','437efe3f-4d10-4281-89b8-123f58a3984d'::uuid,'109f54f9-c153-4282-891a-fb5c323a1fb0'::uuid,'c5bfb169-77bb-4811-8794-f1933665b1dc'::uuid,null,'jentra-w5-load-252-20261008','w5_load_20261008'),
 ('load-253','c9e8f5d5-9f73-4720-8d07-a2e5c4294ee6'::uuid,'765cb575-7d0d-4b68-8045-297ce5e326ec'::uuid,'95e54dbd-3fce-4bd3-8e4d-6f7cf6da95ab'::uuid,null,'jentra-w5-load-253-20261008','w5_load_20261008'),
 ('load-254','7e3fb270-bdcd-4669-842f-916a9e9d74c0'::uuid,'403540c0-f27e-430d-8558-d7f432e07cc6'::uuid,'7fde83cf-7a3f-40a9-8360-c5c70c9f7fd5'::uuid,null,'jentra-w5-load-254-20261008','w5_load_20261008'),
 ('load-255','eeb4b65e-37fa-4759-89d5-e0ae335c1bd6'::uuid,'7daebbd6-5f42-4056-8ba3-c1002b631ffc'::uuid,'efd32252-a8ad-4bf2-8692-04d34baac328'::uuid,null,'jentra-w5-load-255-20261008','w5_load_20261008'),
 ('load-256','ab5fd6bf-db54-4222-8421-96f8b6ed4003'::uuid,'5d779da9-3869-4c83-8f56-86fd30bcf6b6'::uuid,'7bbb7e2f-12ce-436c-845c-0e6a80f90f4c'::uuid,null,'jentra-w5-load-256-20261008','w5_load_20261008'),
 ('load-257','931555b6-02c5-42ef-8650-8102ab999535'::uuid,'232fe1c4-f4ea-4b21-8311-71403fd1811c'::uuid,'8b4867e4-192b-44da-8124-c9b6c6bc58ee'::uuid,null,'jentra-w5-load-257-20261008','w5_load_20261008'),
 ('load-258','9eed10c6-8063-445c-8520-108266220f52'::uuid,'da36dc5f-d5c2-40f6-86ab-9c18fa8331f8'::uuid,'b5bd1861-745e-416a-88e0-0f3c367a17c6'::uuid,null,'jentra-w5-load-258-20261008','w5_load_20261008'),
 ('load-259','37021e77-013f-4102-83c2-37e24f58bd38'::uuid,'588557fc-2808-4e60-819a-2f36ae22658d'::uuid,'007e199c-cd3e-4f28-8824-6a019a5b4e30'::uuid,null,'jentra-w5-load-259-20261008','w5_load_20261008'),
 ('load-260','6a3138cc-10cc-4b02-89cd-7e29928c36f5'::uuid,'d734ddcb-6278-48a1-858e-9ece9a89165d'::uuid,'6e8abeb3-55de-4eef-8bb2-56ed8852dae9'::uuid,null,'jentra-w5-load-260-20261008','w5_load_20261008'),
 ('load-261','50916ab9-fc46-40c7-8e96-d9d908db5e78'::uuid,'54801f7f-a782-42ab-8fd7-7fd16b251519'::uuid,'be3200d5-4f4d-42aa-8d5b-b3a08876333f'::uuid,null,'jentra-w5-load-261-20261008','w5_load_20261008'),
 ('load-262','739d367d-17ec-443f-8f90-d7c536c05dea'::uuid,'5fb11076-5a30-4a02-8b0e-258445e2a50f'::uuid,'5855623b-f87e-4386-806e-ba36fcbff341'::uuid,null,'jentra-w5-load-262-20261008','w5_load_20261008'),
 ('load-263','c13bc441-e575-4408-8e04-3a55031803d3'::uuid,'dc53876c-5575-4eff-81e7-3d8e3caa27b1'::uuid,'f06cd411-4daa-4508-8524-7336fc41847b'::uuid,null,'jentra-w5-load-263-20261008','w5_load_20261008'),
 ('load-264','749f2bca-a0c2-4d17-8985-7cfe17790f1a'::uuid,'46afc738-61a9-44eb-8338-d4408fbbdf10'::uuid,'1aa326a1-a1f7-4ac4-8ce0-85cc9d45115d'::uuid,null,'jentra-w5-load-264-20261008','w5_load_20261008'),
 ('load-265','915ef487-45cb-4fad-8081-d52c5739f29e'::uuid,'b7cfd069-018c-4484-85aa-dac03826b4de'::uuid,'0dc5f103-f617-454e-81ab-1c6d09a75ea9'::uuid,null,'jentra-w5-load-265-20261008','w5_load_20261008'),
 ('load-266','02d65368-34d1-46a8-85af-0dcc0698ce23'::uuid,'430a6b40-a0c4-40ca-83af-a3de9fa3819d'::uuid,'f2cc7c4b-1cf1-48d4-84c7-be4bd44965a9'::uuid,null,'jentra-w5-load-266-20261008','w5_load_20261008'),
 ('load-267','b2bd17fc-3a28-4662-876d-2d20c38e55cc'::uuid,'502f5719-4b69-42d0-889a-443fb1708f3d'::uuid,'19225e0f-8c0b-4f8c-8018-5aba7243bf2c'::uuid,null,'jentra-w5-load-267-20261008','w5_load_20261008'),
 ('load-268','a0f4d798-a5e0-4e24-83c8-3e2de15ae301'::uuid,'6fc5fa19-fd0f-4064-8f25-02651bc75765'::uuid,'3b3d4995-96f3-41aa-881a-5b506e213c7f'::uuid,null,'jentra-w5-load-268-20261008','w5_load_20261008'),
 ('load-269','3858cda9-9cb2-4970-886c-6a6e18866938'::uuid,'04d62216-f72b-4489-8eff-e5a9e46fc925'::uuid,'79df3661-0aa3-43ab-8a32-a9b6816a8a36'::uuid,null,'jentra-w5-load-269-20261008','w5_load_20261008'),
 ('load-270','e74d0796-c5fc-43b6-8582-98e86bc2e68d'::uuid,'c8bf85fb-7592-418c-80c9-edd58cd45083'::uuid,'736d3cb8-5f18-4c82-888d-8386d758aea0'::uuid,null,'jentra-w5-load-270-20261008','w5_load_20261008'),
 ('load-271','523cd390-7169-4fd5-856e-b608dcb10f17'::uuid,'1df06ad2-6bfc-47b7-89dd-92536724b116'::uuid,'3e58a4a4-ee68-4444-85ff-1102c530c8b9'::uuid,null,'jentra-w5-load-271-20261008','w5_load_20261008'),
 ('load-272','8362e296-1d32-4692-8984-2a0e056c7d7b'::uuid,'907d57f6-3ba1-4791-8bc1-7ec6b49fa708'::uuid,'73872cc3-dc6d-4e79-8a1a-ff99afa3331c'::uuid,null,'jentra-w5-load-272-20261008','w5_load_20261008'),
 ('load-273','99598998-8e13-4e3e-87c5-cd33c6b5cddf'::uuid,'b69db20e-9ee5-4747-8e8b-a840db58f37b'::uuid,'b528475b-453b-4b76-8952-8d2a4f3bd6b8'::uuid,null,'jentra-w5-load-273-20261008','w5_load_20261008'),
 ('load-274','8fc43739-146b-437a-80d7-a8d6bba8971f'::uuid,'25549add-5f26-425e-8568-3cc802f20ccb'::uuid,'34a51df3-fc73-4930-8286-f2819ab99cf1'::uuid,null,'jentra-w5-load-274-20261008','w5_load_20261008'),
 ('load-275','01a50bff-87df-4913-80cd-0e00639452d6'::uuid,'1dc67414-705e-413d-8763-82e287c70eb4'::uuid,'32d7ff52-2d43-492c-8fdb-2e2776edc98e'::uuid,null,'jentra-w5-load-275-20261008','w5_load_20261008'),
 ('load-276','c8a4b8a4-ee97-4789-8669-8265e8d61ab8'::uuid,'20f4cea3-7145-4df1-81b0-fab3a3f3d7f2'::uuid,'2e3f53c4-f5c9-400b-80df-825cb6ca6720'::uuid,null,'jentra-w5-load-276-20261008','w5_load_20261008'),
 ('load-277','42398919-acfa-4a74-8773-581c177b3abe'::uuid,'e7b64750-3057-4620-8daf-26be383b754e'::uuid,'4122a5ca-d725-4628-8a50-b705dd10cfb7'::uuid,null,'jentra-w5-load-277-20261008','w5_load_20261008'),
 ('load-278','d10ec069-0546-4129-83c3-e0a4c564a65f'::uuid,'149e821d-dea9-4c4b-86ae-9b2d4b8a3725'::uuid,'be953b5d-cdf3-4add-8752-dfee25680abe'::uuid,null,'jentra-w5-load-278-20261008','w5_load_20261008'),
 ('load-279','7cc81afe-6389-4b0c-80fb-1e6830ccb63e'::uuid,'f936c84b-bf40-44a8-8799-230c6792a476'::uuid,'21642c99-ff17-4857-8acf-541d178d7fe9'::uuid,null,'jentra-w5-load-279-20261008','w5_load_20261008'),
 ('load-280','0ab923be-14ca-45e9-8148-63639dffa1f6'::uuid,'8ea13f4b-d807-48a4-8f87-2a4999a7b9f6'::uuid,'5b68fd4f-2fed-492c-8bf7-8fe13fff06fe'::uuid,null,'jentra-w5-load-280-20261008','w5_load_20261008'),
 ('load-281','c3011a41-3087-4f00-80d1-f268bf446e8f'::uuid,'1189cd31-6a33-4ec6-82ec-7b678bfec96d'::uuid,'5c28cdc3-af11-43e6-856c-b33490b98e1a'::uuid,null,'jentra-w5-load-281-20261008','w5_load_20261008'),
 ('load-282','95d80a45-2035-43c6-8ec0-bb5f741ad613'::uuid,'b5dfe39a-7d9d-45d4-8939-3d35bd24874e'::uuid,'5b581aec-78d9-4f4c-8a4c-cf1583031682'::uuid,null,'jentra-w5-load-282-20261008','w5_load_20261008'),
 ('load-283','316cb9fb-dc48-46e2-840f-440f3822caea'::uuid,'3ac7be3f-4e9e-497a-8094-e1145364c4d6'::uuid,'1f7b27a8-f01c-4eae-80b1-7ed914865e36'::uuid,null,'jentra-w5-load-283-20261008','w5_load_20261008'),
 ('load-284','13e472f1-6b70-4af9-8453-2d04bb35eff3'::uuid,'483933f2-62c4-4b43-8f5c-65294fa3b730'::uuid,'7b02d582-3650-481a-8861-250c4be5ec58'::uuid,null,'jentra-w5-load-284-20261008','w5_load_20261008'),
 ('load-285','81ba99f6-cd9e-468d-877d-6729f5bd93b6'::uuid,'e4fa0812-f10e-40b9-8c27-d52f5e56f546'::uuid,'cae2fe91-1b24-4cf9-8765-aef7cff71c3e'::uuid,null,'jentra-w5-load-285-20261008','w5_load_20261008'),
 ('load-286','1e6d67f4-1cad-437e-804b-ccc398f93d80'::uuid,'91151b5c-6257-4a33-8b4c-e6898cca7d7e'::uuid,'c85b872d-2bcc-4d87-847a-1d96dfc843e3'::uuid,null,'jentra-w5-load-286-20261008','w5_load_20261008'),
 ('load-287','a695322c-2b04-46ae-81b6-c12320ffbfe2'::uuid,'ee718fcc-e148-4d67-87a0-4efed0d50451'::uuid,'808c148c-b34a-425c-8be8-c2e0b69f1525'::uuid,null,'jentra-w5-load-287-20261008','w5_load_20261008'),
 ('load-288','34f6e27c-af4a-4df6-8a35-93cbe9aaddc3'::uuid,'97c85a25-9c0d-4a7d-8527-d09875377ae6'::uuid,'44fabb60-649a-4025-8d3e-7ef82dd888a5'::uuid,null,'jentra-w5-load-288-20261008','w5_load_20261008'),
 ('load-289','c9f045be-f9d4-41b9-875f-9271b9a50121'::uuid,'fd694231-1bd8-4f04-8e14-ae449a0cc9dc'::uuid,'089a20c1-24cf-483c-8973-915452b32937'::uuid,null,'jentra-w5-load-289-20261008','w5_load_20261008'),
 ('load-290','2a323d9b-f1ba-4a7e-87de-d026210d39f2'::uuid,'99d28228-1dab-4e20-8398-d352477a5db2'::uuid,'c6a2ba59-516b-43af-8ef3-2ac0fad129d2'::uuid,null,'jentra-w5-load-290-20261008','w5_load_20261008'),
 ('load-291','b581c62a-1214-4583-8da4-66df81db8b03'::uuid,'7e7e821b-b25a-4c6e-8230-5e8d8600107a'::uuid,'cd75f43d-1712-4259-833d-121153f28d1b'::uuid,null,'jentra-w5-load-291-20261008','w5_load_20261008'),
 ('load-292','2fd04aa9-0a9f-4806-8465-75b2619b7183'::uuid,'0f83dc15-132d-4d70-897f-3858296c66fb'::uuid,'14316a7c-e09b-429f-8363-c6e2f1a2e48f'::uuid,null,'jentra-w5-load-292-20261008','w5_load_20261008'),
 ('load-293','c0ee9a8a-fcbc-4c9d-8e27-58b13ecf74c6'::uuid,'aba24676-dd83-4619-865d-ccf0989a2a8a'::uuid,'403b68fd-e9ea-415e-8286-15d6b6a2641f'::uuid,null,'jentra-w5-load-293-20261008','w5_load_20261008'),
 ('load-294','d2e009bb-3a60-4d62-851f-c240723009ad'::uuid,'abc45b68-e808-4615-86d5-64a1c12edcdc'::uuid,'8cc70a3d-b1d2-40ed-8fa7-2493577d4825'::uuid,null,'jentra-w5-load-294-20261008','w5_load_20261008'),
 ('load-295','8262fca2-c7b9-4385-87a1-b64f0d6e33ed'::uuid,'3e15ba6e-c921-4699-8d43-bad471e06c17'::uuid,'cc18200b-7c6f-41d3-808f-922555af3c4e'::uuid,null,'jentra-w5-load-295-20261008','w5_load_20261008'),
 ('load-296','b14b5f74-aa84-4142-824e-922f73083f98'::uuid,'eeb800e6-f7f9-4f7a-8d33-e9cd94c8f403'::uuid,'c4184bc7-5b79-4a07-8252-011fd681188a'::uuid,null,'jentra-w5-load-296-20261008','w5_load_20261008'),
 ('load-297','8c396d44-4291-4bef-895c-8dffc859a167'::uuid,'e2a01b79-f47d-4af3-810c-39f62c3fee9d'::uuid,'43835a91-976e-41d7-8c68-491f337bcbb7'::uuid,null,'jentra-w5-load-297-20261008','w5_load_20261008'),
 ('load-298','c564b390-4351-4c8d-8f23-1b83d9c68ba9'::uuid,'b638551c-a1e8-4ab4-85ac-eb02460a6789'::uuid,'9326820e-95f0-4136-88e5-49407f711fcd'::uuid,null,'jentra-w5-load-298-20261008','w5_load_20261008'),
 ('load-299','9327d4cd-8848-4af8-86ab-8a3fca0c0957'::uuid,'f0f716f5-3108-46ac-8c69-8476ead3ba65'::uuid,'15145ddf-e8b5-4171-83c7-d7b10b4c0060'::uuid,null,'jentra-w5-load-299-20261008','w5_load_20261008'),
 ('load-300','bfc19d62-acae-4be3-8858-75342feebfb5'::uuid,'b12035b0-9554-4e75-8373-f4be72bc7aeb'::uuid,'e97c72f2-51af-4e90-8cb3-84499fb5d96a'::uuid,null,'jentra-w5-load-300-20261008','w5_load_20261008'),
 ('load-301','f3e49c81-173d-486c-8c49-7efb17c69616'::uuid,'99c9c361-8b3b-4e3f-86d4-558e36fafb75'::uuid,'328fa4f0-1a6e-4b58-8c4f-53c4589b0308'::uuid,null,'jentra-w5-load-301-20261008','w5_load_20261008'),
 ('load-302','a93593b2-8004-4673-8409-0f715d194293'::uuid,'7809b410-db3e-4cce-89fc-f8ae7d763254'::uuid,'57096c01-f9f5-465f-8b4c-d046fd597b85'::uuid,null,'jentra-w5-load-302-20261008','w5_load_20261008'),
 ('load-303','b2f22544-c113-4deb-8d52-1a633edbd4c9'::uuid,'174d1b6f-2a1a-4ff3-8de3-d7f10e7ed43b'::uuid,'d5a1cf8d-4c19-422e-8935-dedcee322c24'::uuid,null,'jentra-w5-load-303-20261008','w5_load_20261008'),
 ('load-304','2f5d1306-aedb-40bd-83eb-02ef5153033a'::uuid,'3b164c91-84e4-4b98-80c0-7e8479920f52'::uuid,'a7580e7e-b3a7-44fd-8d8c-e7afadc9f461'::uuid,null,'jentra-w5-load-304-20261008','w5_load_20261008'),
 ('load-305','4b1733d0-3112-457d-89a7-d6b0cbfbd18f'::uuid,'d6100f50-28b8-41c5-8ee1-04d078d93589'::uuid,'a3c50498-799c-49c5-8409-218e8f1c44c6'::uuid,null,'jentra-w5-load-305-20261008','w5_load_20261008'),
 ('load-306','0ea420ed-c76a-471d-867e-7df51bd93bda'::uuid,'60392f2f-9f05-4dae-8378-61b89333792c'::uuid,'9b74af35-170e-41b8-88e3-727bd470d877'::uuid,null,'jentra-w5-load-306-20261008','w5_load_20261008'),
 ('load-307','bb01c171-434b-46a7-81ff-2506b1ab285c'::uuid,'29f92bf4-eb6b-44a6-8df9-b612381ec610'::uuid,'f0a95e1c-a684-405a-8c5f-1cdd95d0f432'::uuid,null,'jentra-w5-load-307-20261008','w5_load_20261008'),
 ('load-308','69d6990c-a95a-479a-8ecf-5b19b2910849'::uuid,'1777a6ab-2b04-4be2-86de-0067f321333c'::uuid,'eed40f32-d14e-41b1-8924-5d0f88a1f709'::uuid,null,'jentra-w5-load-308-20261008','w5_load_20261008'),
 ('load-309','99da003c-f792-4141-84a8-e93e9869a411'::uuid,'f0ff4a4c-da5e-42a8-82de-810a4c129cc5'::uuid,'ded432a6-bee7-4556-869a-49b1c2e23289'::uuid,null,'jentra-w5-load-309-20261008','w5_load_20261008'),
 ('load-310','394fc37f-b53c-4a34-84fb-0a30c06b4493'::uuid,'91cb3d7d-fc11-4e03-87f1-d36bd0aa0d8c'::uuid,'de6d48d4-e931-4345-8f4d-df94734f760b'::uuid,null,'jentra-w5-load-310-20261008','w5_load_20261008'),
 ('load-311','d87765b6-a4bb-402c-810c-12a8b17d429f'::uuid,'02615635-86e5-4f73-877f-4e3cd82c79cb'::uuid,'74ffe2ba-2b9f-4fdc-8188-c1441d6eaf40'::uuid,null,'jentra-w5-load-311-20261008','w5_load_20261008'),
 ('load-312','07cdbd9b-b6c8-41e7-8e82-9178a366822c'::uuid,'dc84340a-bb32-484d-843b-61d042ac342d'::uuid,'1d70de88-a50e-445c-8f5d-e852984ac541'::uuid,null,'jentra-w5-load-312-20261008','w5_load_20261008'),
 ('load-313','99a3feb9-b4e5-410f-87c9-3a3d6fb88ca0'::uuid,'eb26223e-cf5f-4213-84dd-ff22dafb885b'::uuid,'ca61a841-083b-445f-8dbe-79c2449033a5'::uuid,null,'jentra-w5-load-313-20261008','w5_load_20261008'),
 ('load-314','3d9a79c4-7f89-4d30-8942-50b20fc0c5b1'::uuid,'4802c9c3-902d-433c-8691-83660efe4711'::uuid,'a882dda6-665c-4d72-8541-f66dfd263230'::uuid,null,'jentra-w5-load-314-20261008','w5_load_20261008'),
 ('load-315','3a4b74bb-aa24-44ac-8f49-df21fc453694'::uuid,'dc49c673-bc71-440a-82eb-a0a6a24580b3'::uuid,'a547d3d4-1506-4809-8db9-1f70868b4678'::uuid,null,'jentra-w5-load-315-20261008','w5_load_20261008'),
 ('load-316','6fb9a1c7-dc5e-418f-887e-a6682be21f66'::uuid,'b967ea65-e59a-4051-83d9-820d063993d9'::uuid,'4eb336d3-3288-40ae-8d92-cd233833583e'::uuid,null,'jentra-w5-load-316-20261008','w5_load_20261008'),
 ('load-317','ab2cf896-f0b3-4830-818f-a4b24b303ad4'::uuid,'730eaea8-fefc-4970-8706-b880e49361af'::uuid,'4732cb93-359c-40d6-879b-ab71418a8152'::uuid,null,'jentra-w5-load-317-20261008','w5_load_20261008'),
 ('load-318','feca5daa-9db8-4b3f-8b4d-380a58ee0806'::uuid,'e5268e8d-6ae7-448f-8fe8-1b864f811f34'::uuid,'125bc81d-3627-4da7-8ecc-133ddab6ce08'::uuid,null,'jentra-w5-load-318-20261008','w5_load_20261008'),
 ('load-319','5b225fc0-2ff8-4ea3-8c23-669ba3e004db'::uuid,'5ede6010-3ae0-4ecb-84d2-2753b6b63295'::uuid,'cadb32b7-edec-4c32-8ad7-bb76b1193f39'::uuid,null,'jentra-w5-load-319-20261008','w5_load_20261008'),
 ('load-320','1e19eb08-8464-43bf-8f03-1513b634343b'::uuid,'c0df3cd8-fb25-425a-85a3-22a743dc1bdc'::uuid,'e4dd34c1-adfd-40fc-8e79-b7ef217ffaf7'::uuid,null,'jentra-w5-load-320-20261008','w5_load_20261008'),
 ('load-321','cad6ff75-93e4-4b4b-819e-8e4d3e3a3292'::uuid,'6e3fb900-6df5-4021-8c3b-9ef2f4da759e'::uuid,'54f3df5d-1db9-4e27-855c-1a48209e101e'::uuid,null,'jentra-w5-load-321-20261008','w5_load_20261008'),
 ('load-322','ccffcae7-325a-48c3-85cf-13d0a5d56c8f'::uuid,'a5ae79b0-5322-44ac-8608-9039b14a842b'::uuid,'395e4e73-1c36-476c-8ddd-546f0760763f'::uuid,null,'jentra-w5-load-322-20261008','w5_load_20261008'),
 ('load-323','5fc1516b-2442-4699-8318-92bd0cbc89cf'::uuid,'a5697a6a-f7a1-40f6-80f2-7cdb2114ef0b'::uuid,'0746c279-fd13-4908-87e8-666eb70c915d'::uuid,null,'jentra-w5-load-323-20261008','w5_load_20261008'),
 ('load-324','3a24c3bd-2038-477a-8862-9a70bd66d613'::uuid,'4141cc8d-4e9c-4782-869b-6e7b53f35caa'::uuid,'97374617-ae7e-4fbe-8ccc-b1366bc067a0'::uuid,null,'jentra-w5-load-324-20261008','w5_load_20261008'),
 ('load-325','93cd05c4-d57d-4a20-80d2-8d9e0f5125a8'::uuid,'e50ca6dc-2370-48a4-85bb-ad1c6d669108'::uuid,'df6804c0-3ce5-443c-8cad-b4bd7f062997'::uuid,null,'jentra-w5-load-325-20261008','w5_load_20261008'),
 ('load-326','949fb8e4-db6d-4ecf-84ae-4eff8435817c'::uuid,'a4f2308c-7f6d-4413-8a72-c1983b8b403a'::uuid,'6c45e9f3-1abc-4f0e-896a-bba35b9fe662'::uuid,null,'jentra-w5-load-326-20261008','w5_load_20261008'),
 ('load-327','9770e99c-9ae3-4517-88ee-8d4f2adba39d'::uuid,'cbf5bad5-23f4-42d9-8ac4-e54d9b9fd144'::uuid,'73da4805-68f6-44fc-8752-021fee51f403'::uuid,null,'jentra-w5-load-327-20261008','w5_load_20261008'),
 ('load-328','254ef81c-71e6-48e3-8ff7-6f6172e82a17'::uuid,'6965f987-266b-4c9f-82d2-d078fd424aff'::uuid,'b17f953c-8b45-47b3-845c-20321280364e'::uuid,null,'jentra-w5-load-328-20261008','w5_load_20261008'),
 ('load-329','a016abc6-6390-4db7-835c-12e0d4322f9e'::uuid,'f63b8949-6813-41d1-8003-250c6e705b37'::uuid,'cb031640-db17-4841-8eee-17440f23972e'::uuid,null,'jentra-w5-load-329-20261008','w5_load_20261008'),
 ('load-330','c66cb48d-0f45-416f-8db2-c1b658764e26'::uuid,'1cb358b6-0b7a-490f-86f8-6d06fa3c8e28'::uuid,'3ce2a2f6-8eca-403d-87e5-e9e5fc2098f1'::uuid,null,'jentra-w5-load-330-20261008','w5_load_20261008'),
 ('load-331','0311340c-051e-43ff-8647-fcc171d0ca2f'::uuid,'718c3bf2-eab8-4b62-8189-e8b2c2979a3b'::uuid,'d3a406fa-60e6-4a3d-827a-17d9951a163b'::uuid,null,'jentra-w5-load-331-20261008','w5_load_20261008'),
 ('load-332','833a4c20-a8eb-4164-8b7d-e905e22a5019'::uuid,'18d82e11-2f2b-4d3c-8610-c8b4acdeab75'::uuid,'7e7fb5ec-4430-4bf6-815f-91538af13d87'::uuid,null,'jentra-w5-load-332-20261008','w5_load_20261008'),
 ('load-333','b8ba1030-87f2-4546-8420-b33ef3cc2df7'::uuid,'237beb1a-5504-4de4-8f4a-56bc54d0fef3'::uuid,'d44f2569-2d5b-4bef-8a65-0f1de9398c0d'::uuid,null,'jentra-w5-load-333-20261008','w5_load_20261008'),
 ('load-334','aaa6d5f8-ae3b-4c17-850b-04a12023b2d5'::uuid,'4b46f980-d612-4da7-8391-3046e6e58ae5'::uuid,'d98f41a3-fbe4-4a94-84ad-4cfce963b270'::uuid,null,'jentra-w5-load-334-20261008','w5_load_20261008'),
 ('load-335','60e951d4-6a72-4102-854d-0ce9ac9af52f'::uuid,'edc86a52-e4c4-4523-8f1d-01876c6a3c27'::uuid,'0232c4c9-5551-415a-88a5-c188841e0264'::uuid,null,'jentra-w5-load-335-20261008','w5_load_20261008'),
 ('load-336','0bb07e20-827d-4343-89fd-fef64cdfe849'::uuid,'37911b5e-6c01-4634-8d5f-db9bbf51f506'::uuid,'a10debde-f2b1-4183-864d-4b550a825621'::uuid,null,'jentra-w5-load-336-20261008','w5_load_20261008'),
 ('load-337','f1e63220-29f6-4585-8319-12f60cbbc308'::uuid,'d3d5e6c1-9433-425b-8279-1b9868005a02'::uuid,'8c678672-36b0-4071-8230-6c98a5a6c5fa'::uuid,null,'jentra-w5-load-337-20261008','w5_load_20261008'),
 ('load-338','6d1602e2-f145-4c7f-8ef1-1f2f8eb02243'::uuid,'0858ff14-49cf-48fc-8a40-19c0be2393f2'::uuid,'02327704-3781-439e-86fd-5789e1ab4fca'::uuid,null,'jentra-w5-load-338-20261008','w5_load_20261008'),
 ('load-339','5da8518f-7444-4e56-8c43-26c00688ff9a'::uuid,'37e097af-595a-4030-8d4e-d31e24fd65c3'::uuid,'fbc58184-d4fa-466e-8dfa-c4e34b03eb82'::uuid,null,'jentra-w5-load-339-20261008','w5_load_20261008'),
 ('load-340','00c1ebff-7fb6-4911-8238-f826aa3696aa'::uuid,'2045b0cc-9368-4af3-8374-5cc5e110ab3d'::uuid,'2ff4228e-752f-416b-8c1a-616fb4a5959b'::uuid,null,'jentra-w5-load-340-20261008','w5_load_20261008'),
 ('load-341','b40d42d5-6633-409c-8d95-9ba9b27b2f21'::uuid,'bef5fa3f-92b7-49bd-8126-114ba008ba3b'::uuid,'45c474fc-8bb1-4fab-8ec8-b85c5455322b'::uuid,null,'jentra-w5-load-341-20261008','w5_load_20261008'),
 ('load-342','9212c28d-6383-4464-8916-c6606a2f54cf'::uuid,'46c91911-6076-42ec-8acd-e085db50b15f'::uuid,'6172c9f0-8f55-4cb0-88c0-a52297a2ce10'::uuid,null,'jentra-w5-load-342-20261008','w5_load_20261008'),
 ('load-343','147e1ce1-be19-4526-8b49-cb56fe8b498a'::uuid,'e286de6f-f9c7-4943-8104-014a536fbd3f'::uuid,'9ffb2798-bf59-4e19-8fa1-cd2ca5620b3d'::uuid,null,'jentra-w5-load-343-20261008','w5_load_20261008'),
 ('load-344','32e300f5-02e3-4e13-8be5-961e98f74ce4'::uuid,'92d2c641-43a3-4722-8d8b-766bcff905ac'::uuid,'53dccca7-6186-4ab5-8c54-0ea6461ea12b'::uuid,null,'jentra-w5-load-344-20261008','w5_load_20261008'),
 ('load-345','5beeb777-fc79-41b7-8427-457b133e7c56'::uuid,'310b3542-9b73-4c6e-8720-8b473c9459fb'::uuid,'ccc5c429-0638-4a7c-8e0f-cf8edd465873'::uuid,null,'jentra-w5-load-345-20261008','w5_load_20261008'),
 ('load-346','f860fd39-8b0c-4956-8162-0dbe23a34087'::uuid,'fc444b6f-9b6e-4e05-89fc-f6bbb7d509eb'::uuid,'23b11cd5-ee8b-419c-8642-8843a95d6309'::uuid,null,'jentra-w5-load-346-20261008','w5_load_20261008'),
 ('load-347','1a398f44-2b21-4dda-8fe7-92dd6766577b'::uuid,'98fdcc91-f5de-485c-8039-01b279b3f4ca'::uuid,'e19b71e1-f9a2-418c-8d00-25fc6143db42'::uuid,null,'jentra-w5-load-347-20261008','w5_load_20261008'),
 ('load-348','13ae1d32-0941-4d33-8d3c-b2ecda7511ff'::uuid,'3f83c5df-141f-4392-8dc7-33f396258537'::uuid,'b7a7259a-b65f-4a89-8aa7-1394df7321ca'::uuid,null,'jentra-w5-load-348-20261008','w5_load_20261008'),
 ('load-349','b23de00a-f520-491d-81d0-ca0245c1d3f9'::uuid,'f5baeebe-9bd1-43c6-826f-cb92b81af587'::uuid,'b29efaa8-dd07-488d-8c53-a3ca939af3b0'::uuid,null,'jentra-w5-load-349-20261008','w5_load_20261008'),
 ('load-350','6e133f0c-dd0c-43cc-85f8-a7b431124dd4'::uuid,'a6b1bc31-8349-40cb-8599-45d8bbae1a0b'::uuid,'7fcfafc4-0dec-49a3-8a31-9c7bfa322fa5'::uuid,null,'jentra-w5-load-350-20261008','w5_load_20261008'),
 ('load-351','19f45d27-20ff-4fb9-80f4-1d899855b219'::uuid,'943359fa-1371-488d-8d58-b94efc24e053'::uuid,'d5d536de-a613-4216-861d-d3a33f3268ac'::uuid,null,'jentra-w5-load-351-20261008','w5_load_20261008'),
 ('load-352','37dc37d2-f4a2-438b-83ce-7d45e98039e9'::uuid,'57f48ccb-54aa-4ac4-8d26-8001ffbea70d'::uuid,'d705b4d9-d395-4dd4-815a-950589924547'::uuid,null,'jentra-w5-load-352-20261008','w5_load_20261008'),
 ('load-353','7f6240e4-3b1a-4531-85a8-029181fab5ff'::uuid,'34fb6459-754f-4863-8200-d1257381557c'::uuid,'4bee7af2-b9a7-4d46-887b-dc5011677f4f'::uuid,null,'jentra-w5-load-353-20261008','w5_load_20261008'),
 ('load-354','ea3e261b-c9f1-4e74-83b7-4a16e7891eae'::uuid,'e7baae07-5606-41ab-806a-56c9c33c28f3'::uuid,'fde51a82-d1a5-4ca1-8c95-c3c790a8845b'::uuid,null,'jentra-w5-load-354-20261008','w5_load_20261008'),
 ('load-355','fcd700a4-188e-41aa-869b-a671e87768dd'::uuid,'da9f7f61-d617-4b7f-808c-ee0c281980d0'::uuid,'2f759715-189d-4e99-864e-e32b1bf08a52'::uuid,null,'jentra-w5-load-355-20261008','w5_load_20261008'),
 ('load-356','1e633b39-0f17-46d2-8128-42bb654e3a0d'::uuid,'d890428f-557b-4ada-8c07-bafca78dd7e6'::uuid,'95ea734a-814e-4ea6-839c-4afb40f7d61d'::uuid,null,'jentra-w5-load-356-20261008','w5_load_20261008'),
 ('load-357','936810bd-f3c5-4993-8e61-0011e1975ed7'::uuid,'62a04933-53ea-4607-8da8-f47faa674a0b'::uuid,'b8dc88a2-309c-4404-8360-2b0d45f3adba'::uuid,null,'jentra-w5-load-357-20261008','w5_load_20261008'),
 ('load-358','57f729b6-1120-49dd-8acf-51714ad590ba'::uuid,'f7dbc976-7dbe-42f7-8a3b-8cdaa9b9dacc'::uuid,'a41c4c4b-a23d-414c-8386-8be1824b00ee'::uuid,null,'jentra-w5-load-358-20261008','w5_load_20261008'),
 ('load-359','302de338-6855-4024-870c-bfdeb8a4b3e0'::uuid,'db46f039-984a-4fab-8fed-f5ea87142256'::uuid,'0e87e5a7-8f1b-4edf-80d1-73b0cd05cdfe'::uuid,null,'jentra-w5-load-359-20261008','w5_load_20261008'),
 ('load-360','44118a3d-c2b7-42a7-8eea-4d7cdf202866'::uuid,'66896364-3f91-469a-870a-89620452c763'::uuid,'873c1261-aaa7-4a1c-85cf-04d041d322e8'::uuid,null,'jentra-w5-load-360-20261008','w5_load_20261008'),
 ('load-361','d0a13f6b-94b0-4621-867f-7ca77b5ad71f'::uuid,'9e16cf86-080d-490f-8a4e-de75eae23d76'::uuid,'b0880477-c159-498e-85f3-48fd8e04a7ed'::uuid,null,'jentra-w5-load-361-20261008','w5_load_20261008'),
 ('load-362','d9ccbeaa-94e4-4e6c-8edb-7b195e841abf'::uuid,'89175df2-2f14-48c1-866a-f5221aee3a3b'::uuid,'a2202dc5-1a89-4423-8456-4be288891a9d'::uuid,null,'jentra-w5-load-362-20261008','w5_load_20261008'),
 ('load-363','9fb86c44-d773-4167-8968-0dab883b63f2'::uuid,'8ca07d9e-2e0e-424e-8f46-518f8894fb6e'::uuid,'bac8d5b9-699d-41f8-8462-7f52fa69875e'::uuid,null,'jentra-w5-load-363-20261008','w5_load_20261008'),
 ('load-364','5f8b0ee1-80c8-46f2-8606-6ef4a3a1842f'::uuid,'2ab91995-7222-47ae-800e-4e575f02a01d'::uuid,'2bbd60b8-63ee-4aea-8b29-6cb2de692cc3'::uuid,null,'jentra-w5-load-364-20261008','w5_load_20261008'),
 ('load-365','a7ce7ea3-f6ac-4f9c-8f99-5c6ffdd57f02'::uuid,'215cd99e-c955-4516-817d-9cfed318ba6a'::uuid,'808de1f7-d683-4d3d-8e27-ed54920e7907'::uuid,null,'jentra-w5-load-365-20261008','w5_load_20261008'),
 ('load-366','4fa57b99-e8a2-4074-88c0-75fb4b1a5954'::uuid,'50645503-381d-4094-84e0-1328a7b2fc8b'::uuid,'1c97f9b3-173d-46a4-80c5-d52ae28ea8f8'::uuid,null,'jentra-w5-load-366-20261008','w5_load_20261008'),
 ('load-367','13f2596f-6552-446c-86f9-67d6384ce845'::uuid,'f3ad8bab-c35f-4a3d-8dfa-53a78d7231ca'::uuid,'8d40772e-9508-4241-82a1-840d8bf1689d'::uuid,null,'jentra-w5-load-367-20261008','w5_load_20261008'),
 ('load-368','cc573650-9f31-4dc9-8273-50eed02bfff4'::uuid,'3d24068e-d1f7-47bd-804e-cee3d723e018'::uuid,'30e142c7-bd71-4386-83d9-2b253b3fb05e'::uuid,null,'jentra-w5-load-368-20261008','w5_load_20261008'),
 ('load-369','4c5e8362-807d-41f9-8a1c-5731794d472a'::uuid,'46d7181b-fa02-43e3-800f-60d46c897c32'::uuid,'913eec01-292c-459e-8f80-4972a8ff76b6'::uuid,null,'jentra-w5-load-369-20261008','w5_load_20261008'),
 ('load-370','6841b66f-1aa8-481e-8541-5825ee7416f7'::uuid,'bd9431e3-a737-4ac2-81b6-79dd691d1585'::uuid,'53975e66-188a-4cf9-8ab8-7ddb58c07959'::uuid,null,'jentra-w5-load-370-20261008','w5_load_20261008'),
 ('load-371','b1c790f6-b269-4d98-88b0-952c667ef9cd'::uuid,'0d3a630f-cd14-4716-8820-49860e5998bc'::uuid,'bb6de346-ba09-4f6e-8313-0adecfb65e85'::uuid,null,'jentra-w5-load-371-20261008','w5_load_20261008'),
 ('load-372','7fb6dabc-1575-415d-8344-e085b16ffeef'::uuid,'615865e5-6edb-469a-8e14-50d8dcaa1ad5'::uuid,'bae95395-5d78-43d5-8579-0f03b5a7520d'::uuid,null,'jentra-w5-load-372-20261008','w5_load_20261008'),
 ('load-373','5ea58ffd-80e3-43cb-8f81-02b00f8daf08'::uuid,'3c0cee8e-0e2f-42c6-8ceb-c278b7c601ad'::uuid,'aecd7f4b-1998-44b4-80dc-a18e7ba359ab'::uuid,null,'jentra-w5-load-373-20261008','w5_load_20261008'),
 ('load-374','b686ed62-5d46-44b1-8d5d-ae786bd67b9c'::uuid,'27ce9e27-2794-4b9d-82c4-af277b46e2cb'::uuid,'fefb9629-287b-4048-8564-4e9400591c39'::uuid,null,'jentra-w5-load-374-20261008','w5_load_20261008'),
 ('load-375','2c37251e-64b7-4fb1-820a-7a3388e1a746'::uuid,'2d819d54-6c41-4652-8336-9b17e271bc0f'::uuid,'cf8146aa-63aa-4aab-8e59-4ee961b62cde'::uuid,null,'jentra-w5-load-375-20261008','w5_load_20261008'),
 ('load-376','e1aa09c3-7595-4666-869f-ad7e910259d7'::uuid,'22fb94c3-00bd-432a-8b1c-7c1909fc1a0f'::uuid,'b4cf7662-cb31-4550-8c1e-08ceaa3c8e1d'::uuid,null,'jentra-w5-load-376-20261008','w5_load_20261008'),
 ('load-377','ecbbbb27-7057-41be-824e-ea07261ebc39'::uuid,'a047e05b-0639-479b-84c8-89c6eb1f9459'::uuid,'31f4a65d-96f1-4904-8a15-33e5ddd31530'::uuid,null,'jentra-w5-load-377-20261008','w5_load_20261008'),
 ('load-378','55d1a7e0-412f-42f0-848f-d941f2c50e98'::uuid,'290c1c83-9ccf-4684-8cbf-4bfc6b895c41'::uuid,'dc34572d-a30a-4ae8-8044-d43a820de9e1'::uuid,null,'jentra-w5-load-378-20261008','w5_load_20261008'),
 ('load-379','78d1e0b0-b0c4-4e04-8a4c-32fc0bebb3fa'::uuid,'fda3d122-e39c-4112-849b-0c2276d90a78'::uuid,'7b738221-d202-4446-8b8c-b2bba75672ed'::uuid,null,'jentra-w5-load-379-20261008','w5_load_20261008'),
 ('load-380','266410db-0000-41dd-8aae-2fbeb927e83f'::uuid,'057cc37a-d47e-4265-8581-69c295f5f5e1'::uuid,'40a60b62-cbaa-4534-874e-6ca74514dc8b'::uuid,null,'jentra-w5-load-380-20261008','w5_load_20261008'),
 ('load-381','4b077dcf-ccb6-4672-8781-80883af3c4ff'::uuid,'a7fe1e0c-bef8-4d19-84ad-afef1b60f5e8'::uuid,'9f8d93c2-1f90-4528-83c9-1fcb069b73f0'::uuid,null,'jentra-w5-load-381-20261008','w5_load_20261008'),
 ('load-382','9e9dd40a-a8a5-4124-86ed-ca0bae8c8607'::uuid,'24785f69-dc02-4feb-8630-f6d2843f49d2'::uuid,'782dd765-14b6-478a-8cc7-1ef6ab337f59'::uuid,null,'jentra-w5-load-382-20261008','w5_load_20261008'),
 ('load-383','409f5e5b-bb60-4df9-8be1-1ee91e6c827a'::uuid,'5a08468e-5736-47d5-8fb1-16d268950dce'::uuid,'2f5c81f6-6123-488c-8808-eb0464605583'::uuid,null,'jentra-w5-load-383-20261008','w5_load_20261008'),
 ('load-384','0ff3c42f-0fea-4dfb-8bd6-aa722d78055e'::uuid,'cdb127f0-4705-4232-8e95-7b5370381067'::uuid,'90f5d78d-63c7-4db6-87e1-cb053b2380f8'::uuid,null,'jentra-w5-load-384-20261008','w5_load_20261008'),
 ('load-385','1dc844ee-48ad-49b1-8abf-707d45b55518'::uuid,'5ca59b05-6589-4d74-8709-25d79ffb8a2e'::uuid,'71ddb783-80de-4213-8a60-257831e98c29'::uuid,null,'jentra-w5-load-385-20261008','w5_load_20261008'),
 ('load-386','8f0fcc22-5322-4d09-80a0-b77b9e2dd380'::uuid,'0746d5e8-6467-4262-85b8-d1a81cb1f322'::uuid,'cdb986a1-bbb6-4e8e-8c70-3b7194ac7f10'::uuid,null,'jentra-w5-load-386-20261008','w5_load_20261008'),
 ('load-387','57890d6b-3cc9-4f79-8a6d-229b3f2fa48c'::uuid,'542c2051-9163-4793-88a2-c8eed73a5356'::uuid,'905114a1-c22a-4cf8-82cb-bf2e2be81ce5'::uuid,null,'jentra-w5-load-387-20261008','w5_load_20261008'),
 ('load-388','0cfde7da-5253-4182-8ecc-74be62be4859'::uuid,'7b4e8180-343a-4ffb-83c4-e141088dc463'::uuid,'58add264-8bb1-4934-8f74-2781c3a2a6e0'::uuid,null,'jentra-w5-load-388-20261008','w5_load_20261008'),
 ('load-389','6a2ba1d8-37cd-437f-8d30-660714312bff'::uuid,'9312e634-8911-46c3-802f-e3a9c443651a'::uuid,'2661a133-cd52-40bb-83b9-5d0c53b777dd'::uuid,null,'jentra-w5-load-389-20261008','w5_load_20261008'),
 ('load-390','c4a9a550-4e27-42ca-8a2d-b47aacda512c'::uuid,'30f6b027-ce8b-47a9-828c-01bfe5de1b5f'::uuid,'7797cf24-8995-4154-8a4c-d2463c6fe218'::uuid,null,'jentra-w5-load-390-20261008','w5_load_20261008'),
 ('load-391','f8b198ed-bfea-4a20-8657-32685701a488'::uuid,'eecefc7d-9a5d-42a0-89ee-7260600f5b33'::uuid,'68c3e190-ffd5-4949-8e75-6b57eeb92f21'::uuid,null,'jentra-w5-load-391-20261008','w5_load_20261008'),
 ('load-392','660911e7-91db-4254-842c-14aa930a017d'::uuid,'433c3034-e1f8-4063-86fc-71456041151f'::uuid,'a2254feb-8c2e-477b-8df8-91c3d52e5b63'::uuid,null,'jentra-w5-load-392-20261008','w5_load_20261008'),
 ('load-393','bdcea603-da09-474c-8a9d-1671a24ae396'::uuid,'ee629b6e-246a-491c-873e-c1b82a2dde47'::uuid,'03373873-8346-412a-8c1c-afb366a7aac9'::uuid,null,'jentra-w5-load-393-20261008','w5_load_20261008'),
 ('load-394','4502b65f-63ff-47b3-8ab6-861e98a96f4b'::uuid,'cf957509-cf6f-437a-8776-3c11e7eba25a'::uuid,'5e5694c6-ad52-4fbc-8331-64df4a580f67'::uuid,null,'jentra-w5-load-394-20261008','w5_load_20261008'),
 ('load-395','ab26a0dd-4c12-4779-860f-94944de9477b'::uuid,'b871e2d4-0cb8-433e-8912-2c9f0d5bfc9e'::uuid,'a3cc5fc2-2010-4c9b-8ccc-245172e67261'::uuid,null,'jentra-w5-load-395-20261008','w5_load_20261008'),
 ('load-396','99459e6b-6e52-4310-8ea0-4863af91f01d'::uuid,'f5f4a974-82ad-4f61-8971-bef58a75af35'::uuid,'6849539d-76f1-4c9a-89db-83121cae5ea0'::uuid,null,'jentra-w5-load-396-20261008','w5_load_20261008'),
 ('load-397','add74ea6-8cd3-4820-8f7c-010891a9e454'::uuid,'33751073-28f8-468a-8ee0-f1f1988ef3b9'::uuid,'4c174e68-776f-4fdd-87f1-24f6c8f54656'::uuid,null,'jentra-w5-load-397-20261008','w5_load_20261008'),
 ('load-398','586964c3-1775-485a-8f35-e90581742305'::uuid,'18633d29-bfb4-44d3-80e3-dacf9663ca42'::uuid,'1ac94b3e-a2bb-48ad-8d3a-3bb681821419'::uuid,null,'jentra-w5-load-398-20261008','w5_load_20261008'),
 ('load-399','8131e4e3-9107-4df0-8b53-70e7de4980d0'::uuid,'00759d89-89fc-4d97-8e6c-02a5b3bf7f79'::uuid,'33f86a8a-00c2-468e-87d4-6bdf34af020e'::uuid,null,'jentra-w5-load-399-20261008','w5_load_20261008'),
 ('load-400','1ef7dff3-5c07-4f04-8ec5-cbc8884a338c'::uuid,'90296717-6629-4c6a-8b6e-f56e66c2172c'::uuid,'92083aa5-9f67-485e-84df-d4e56c9548d0'::uuid,null,'jentra-w5-load-400-20261008','w5_load_20261008'),
 ('load-401','34aab5af-8dfd-4153-8a88-c4d8b345b211'::uuid,'86883d86-9601-4f26-87fd-792d401f5b7a'::uuid,'442b182c-0f10-4208-87b9-9393fb70c8e8'::uuid,null,'jentra-w5-load-401-20261008','w5_load_20261008'),
 ('load-402','80dca334-7ff7-46af-8069-0a9434cce68b'::uuid,'445bf97f-fe78-4215-828b-5e1618446fe6'::uuid,'d8e14c0c-ced5-4842-8d89-9e0faa209a45'::uuid,null,'jentra-w5-load-402-20261008','w5_load_20261008'),
 ('load-403','fd64d9e9-9654-407a-8b44-e39c4159560e'::uuid,'70dcc3ee-e269-4330-8d26-2712246cc13e'::uuid,'490a9710-1a3f-4fc3-8f79-e84f888669be'::uuid,null,'jentra-w5-load-403-20261008','w5_load_20261008'),
 ('load-404','cf79df48-583c-4c54-8645-6b7c3d521132'::uuid,'ba2cf438-d8bb-4cf3-8ee8-f97ff29c86f6'::uuid,'8227b52c-d788-4705-897a-3d54f9947774'::uuid,null,'jentra-w5-load-404-20261008','w5_load_20261008'),
 ('load-405','fc7e4874-0ce0-4eab-83ad-315bceb564b0'::uuid,'49d42aea-5e0c-4efd-8d0d-2d82a15ed748'::uuid,'debff916-5fc5-4a50-810d-d204938edf5f'::uuid,null,'jentra-w5-load-405-20261008','w5_load_20261008'),
 ('load-406','215520a3-5129-4913-8e1d-6de045f48ed2'::uuid,'ddd971ab-2dd4-4ef4-8c68-c635aeda65d6'::uuid,'47de022d-758a-4cb3-89af-cebe4e3dcdf7'::uuid,null,'jentra-w5-load-406-20261008','w5_load_20261008'),
 ('load-407','b651a8b6-720b-4661-85c3-bb3c41784be8'::uuid,'77a905bd-6673-436a-8cd7-2921079e0a34'::uuid,'0eb1b6c3-6716-4fa9-82e5-42aa3ee70375'::uuid,null,'jentra-w5-load-407-20261008','w5_load_20261008'),
 ('load-408','28669f9f-3401-41a0-80d6-b60f9d610828'::uuid,'9f4a28b4-d4f4-4449-85ef-10584c3ea5eb'::uuid,'ad38dae4-ccfb-4b31-8f63-767549971efa'::uuid,null,'jentra-w5-load-408-20261008','w5_load_20261008'),
 ('load-409','a4cd8cfb-8c8a-49a5-8d4a-edba46828d00'::uuid,'4e8ae5a5-1a83-47b1-81ea-ddd00de0cc6d'::uuid,'a41e558b-f19e-400d-895c-87cf15f98016'::uuid,null,'jentra-w5-load-409-20261008','w5_load_20261008'),
 ('load-410','6fac7fe0-5267-4f17-8274-dcac808aaed1'::uuid,'672eeecd-5a49-415e-824d-1cc91dc9a99f'::uuid,'044686ad-b6fc-426f-8fc8-670d9709f98a'::uuid,null,'jentra-w5-load-410-20261008','w5_load_20261008'),
 ('load-411','bbeb2fc3-0f1f-45c0-8ccd-e8055b995ed4'::uuid,'6c63ea2f-ce87-40a9-8236-87abbbe3df95'::uuid,'f626f754-dc89-4b5f-892d-05c6de845978'::uuid,null,'jentra-w5-load-411-20261008','w5_load_20261008'),
 ('load-412','e792ae16-4831-4a6f-8f55-dd187fa64f4b'::uuid,'330cee02-ccdc-4bd5-8b32-97a46863f764'::uuid,'d9f7fa62-9ae7-49fe-8b83-16ad57082c55'::uuid,null,'jentra-w5-load-412-20261008','w5_load_20261008'),
 ('load-413','a732a2e8-fdfb-4afc-81e5-7f6f430f9fd9'::uuid,'89926607-3eec-4d4c-8b15-c446bf6719b7'::uuid,'2bf48012-cdc7-40b5-8170-3a904994506b'::uuid,null,'jentra-w5-load-413-20261008','w5_load_20261008'),
 ('load-414','3ec89122-3bd3-4ca3-8ae3-7bd66630d2b6'::uuid,'2d461b70-4e83-45df-8169-308eb6fa953d'::uuid,'a3d917e6-3177-41d1-8860-ec9e288c3cbf'::uuid,null,'jentra-w5-load-414-20261008','w5_load_20261008'),
 ('load-415','a7d72eb0-1294-4356-889a-b12929eee5ce'::uuid,'cb967aea-3ecb-4e0b-8d12-9be70f050b18'::uuid,'8877784b-f85c-42f2-8d1c-cc104bc0841f'::uuid,null,'jentra-w5-load-415-20261008','w5_load_20261008'),
 ('load-416','b3e81604-796b-4912-8ef9-10c7a542e993'::uuid,'079d4894-3412-492b-88c8-9dbcc1a1fb27'::uuid,'21e059da-c277-4cf6-8186-519901dc3d04'::uuid,null,'jentra-w5-load-416-20261008','w5_load_20261008'),
 ('load-417','3c16174f-89ae-4fe8-889f-44e0f5950e44'::uuid,'ec3d4145-d1d7-4d7d-8f4a-b9e6c1852af9'::uuid,'744f627a-1d32-44f6-8e70-53062bfd1943'::uuid,null,'jentra-w5-load-417-20261008','w5_load_20261008'),
 ('load-418','8231def5-92f0-4fef-8c11-7baff5f1e9c8'::uuid,'a1c03857-bd0c-4b80-8a58-70a572cef1c8'::uuid,'53662234-6692-41e2-8695-4c806f86425e'::uuid,null,'jentra-w5-load-418-20261008','w5_load_20261008'),
 ('load-419','459f9170-1822-45ec-8c7f-6727c1db6565'::uuid,'ac2c1e49-50a4-406b-8f01-1b426d567f25'::uuid,'695aa1a0-6fbd-4fc5-8fa8-2754ca219b9b'::uuid,null,'jentra-w5-load-419-20261008','w5_load_20261008'),
 ('load-420','310b6535-7643-4d73-85af-3898a03f56af'::uuid,'b9807a97-107d-4ebf-82cd-7fe75acdafab'::uuid,'59cc8da1-fba9-4a66-805b-1fa976cff2f1'::uuid,null,'jentra-w5-load-420-20261008','w5_load_20261008'),
 ('load-421','036d67fb-11a9-4851-8a21-374b9aa1637a'::uuid,'f425c33c-4948-42ea-8611-b1a5f155d08f'::uuid,'128af76e-eebd-4281-81c8-7b234b72a932'::uuid,null,'jentra-w5-load-421-20261008','w5_load_20261008'),
 ('load-422','6b1404e7-c28a-4ce6-8fe7-4af2bf138b03'::uuid,'5693c6b2-8c45-431f-8fbc-40a332542e90'::uuid,'58c13ac1-580b-4e0c-81af-2ab886168cd9'::uuid,null,'jentra-w5-load-422-20261008','w5_load_20261008'),
 ('load-423','e7afa70f-4f28-4ccb-81e6-51684e2cdab2'::uuid,'5a4500be-5be9-4dc9-84d4-326aa1e96573'::uuid,'3a00f70d-cd55-4656-87e7-9bbc4ea7c378'::uuid,null,'jentra-w5-load-423-20261008','w5_load_20261008'),
 ('load-424','18a461f0-7542-4fc3-8f7a-f0a5bacb40bc'::uuid,'1c014625-9278-41bc-85aa-ee30b4d18d4b'::uuid,'e462bf8a-bcba-4c2c-8518-19fcea6f96e8'::uuid,null,'jentra-w5-load-424-20261008','w5_load_20261008'),
 ('load-425','4d7cc3f7-ce3b-4bba-89f6-6ca53a76db01'::uuid,'b96ae892-5a7d-426f-8e46-a059767de037'::uuid,'37eb5220-6acf-4ba2-82ed-f19ec5df37db'::uuid,null,'jentra-w5-load-425-20261008','w5_load_20261008'),
 ('load-426','3fb03146-7c8c-4f19-863f-023a0d1e405c'::uuid,'65887e2c-bbfe-41a3-8638-6e076eb81b3b'::uuid,'3e4ca861-65d8-4815-8fa6-b126ed678a5b'::uuid,null,'jentra-w5-load-426-20261008','w5_load_20261008'),
 ('load-427','639e85b3-68b6-4bb9-875d-ef190423ca99'::uuid,'330eb301-5e87-4c7c-8a8b-39a843dc01d3'::uuid,'beb47131-d762-4bfe-89f5-df02d73ff51a'::uuid,null,'jentra-w5-load-427-20261008','w5_load_20261008'),
 ('load-428','838d1903-32a3-4855-815b-b79f4687919b'::uuid,'786c7551-5f30-421e-8e3f-f1ea9a5a2c2b'::uuid,'cf673498-8271-48b6-8d38-dc76ee968410'::uuid,null,'jentra-w5-load-428-20261008','w5_load_20261008'),
 ('load-429','cbaff433-33ac-48a4-8995-59d7e69c1921'::uuid,'07c95c2c-667f-4efb-8035-17d67a72b55c'::uuid,'525c3640-0cc6-4ed4-8b27-8ef74c827666'::uuid,null,'jentra-w5-load-429-20261008','w5_load_20261008'),
 ('load-430','1927a3a1-3759-4273-8bb9-de5508bd8147'::uuid,'464e229f-fee7-4ff6-890a-f5537648810c'::uuid,'f2d6684d-558f-4a13-8663-66c2d3fedea0'::uuid,null,'jentra-w5-load-430-20261008','w5_load_20261008'),
 ('load-431','c4df6e8b-1400-480e-8d00-f44b39f17cbd'::uuid,'37fb0ccb-82fc-47b6-81af-996ce7c73a96'::uuid,'ca39371c-7303-4936-823b-777a73de4a86'::uuid,null,'jentra-w5-load-431-20261008','w5_load_20261008'),
 ('load-432','a2d05520-1028-4c0e-809b-6f34c86bec32'::uuid,'48c19a44-cb67-4ec7-89b4-4ebf46e09193'::uuid,'66f38639-232b-4158-846d-392239adc6da'::uuid,null,'jentra-w5-load-432-20261008','w5_load_20261008'),
 ('load-433','84ea827e-6d19-44cd-86f9-78105ce07903'::uuid,'9a43cf41-9755-4951-88b8-bf949c8b1205'::uuid,'e08e2bc6-7bdb-477e-87e7-05e5ac5327df'::uuid,null,'jentra-w5-load-433-20261008','w5_load_20261008'),
 ('load-434','f098d0f6-c382-4731-82cd-276e98fa9330'::uuid,'79bbc6e2-92ac-4fd0-8c1b-1cd807b2b5be'::uuid,'913de501-0b07-42e7-80ac-e349e577e19e'::uuid,null,'jentra-w5-load-434-20261008','w5_load_20261008'),
 ('load-435','98028273-419e-4a95-8b92-0a66ae687f4a'::uuid,'be827a60-6ec7-4b5c-8175-7a3010dce3a0'::uuid,'33b60a0e-dbe9-4c75-8da1-05b83966d8ca'::uuid,null,'jentra-w5-load-435-20261008','w5_load_20261008'),
 ('load-436','97a5c5a6-d533-4d9c-8fb0-acfb9b018ad0'::uuid,'f91f9050-c197-401d-8ada-e36a3e950dd5'::uuid,'893c814d-7e84-4a25-8df2-6b017d3a0b81'::uuid,null,'jentra-w5-load-436-20261008','w5_load_20261008'),
 ('load-437','c4b735d6-b68a-4fd9-8112-e6d5be80cef8'::uuid,'a3d1fe3c-1ec1-4955-8eb9-6d7b16fc1aec'::uuid,'74b7f73f-6c0b-44b1-8e3c-2ab3352b0d31'::uuid,null,'jentra-w5-load-437-20261008','w5_load_20261008'),
 ('load-438','e7a487c8-24fb-4b02-8412-4c80fa9ef0b5'::uuid,'faf98fc2-5d5c-4601-8a12-a063d9128506'::uuid,'8910b1f1-af2f-4939-8958-9699a03d0224'::uuid,null,'jentra-w5-load-438-20261008','w5_load_20261008'),
 ('load-439','78e62e33-b6f1-4210-87d4-b35729995d8b'::uuid,'3c4216aa-753b-48ae-8e70-ef83203cab96'::uuid,'e0e09f81-131c-4624-885b-0ddd7862243a'::uuid,null,'jentra-w5-load-439-20261008','w5_load_20261008'),
 ('load-440','a626b497-ba02-47e4-813a-13424e4c0fce'::uuid,'1ed0c40a-3c66-43a8-8a1f-93b2542cb18e'::uuid,'58ccfb8e-9b65-4f04-83ec-4cc815b2f09e'::uuid,null,'jentra-w5-load-440-20261008','w5_load_20261008'),
 ('load-441','d1c95d28-78c7-485c-8910-66fc4a708556'::uuid,'c5c974f2-eff0-4e67-868b-692447fe86b5'::uuid,'e3820a4c-6c0a-41cd-8643-a9f7094e74a1'::uuid,null,'jentra-w5-load-441-20261008','w5_load_20261008'),
 ('load-442','1dc055c2-d213-4571-8a90-67e749515b08'::uuid,'a90c559f-0123-4975-8922-2fbc6dd5ea86'::uuid,'2c02cfb5-4e15-44fa-835b-62c26eff3fd2'::uuid,null,'jentra-w5-load-442-20261008','w5_load_20261008'),
 ('load-443','9d1e1333-d1f4-4e62-81f8-050d18850ff3'::uuid,'522533ee-b1e6-40af-8750-caf6c6a0b1cf'::uuid,'c5f20041-b592-4103-8c3e-d6d7c11cb45e'::uuid,null,'jentra-w5-load-443-20261008','w5_load_20261008'),
 ('load-444','edf0672f-f3d7-4940-847d-2096e138eeb5'::uuid,'312e16c4-6305-4a03-8038-a2370e5e5557'::uuid,'2eb00f12-fc70-4afb-8d0e-fa4c5595d88c'::uuid,null,'jentra-w5-load-444-20261008','w5_load_20261008'),
 ('load-445','198cf2cc-88dc-41e7-8106-02bac3796cc8'::uuid,'b71e170d-e415-4040-895e-7e4db511f9f6'::uuid,'26db27a4-d595-4841-8edb-43dc775c8dbb'::uuid,null,'jentra-w5-load-445-20261008','w5_load_20261008'),
 ('load-446','e680bc2d-d289-42a7-8bf6-e67ddbbec387'::uuid,'78862884-f9d9-4432-84dc-08162dde1db5'::uuid,'76fac4e1-4f0e-4d82-8087-aeb1b6933b37'::uuid,null,'jentra-w5-load-446-20261008','w5_load_20261008'),
 ('load-447','a51cbc51-b209-4e30-870d-3acb24d2d3a1'::uuid,'ed7ff4a4-ae0f-4086-8fcb-aab7662da8ac'::uuid,'000b5af5-71a4-437c-85b4-cccee358686a'::uuid,null,'jentra-w5-load-447-20261008','w5_load_20261008'),
 ('load-448','b95544c7-f0dd-4337-85b7-525ea906e69c'::uuid,'378cdee5-7039-4c18-801a-f8ae82d40c72'::uuid,'da4813f8-6596-4ec5-8db7-ace6a24fae37'::uuid,null,'jentra-w5-load-448-20261008','w5_load_20261008'),
 ('load-449','468ea760-da97-428b-8aa3-dff9d7cce110'::uuid,'063582e7-2ca5-44e6-8398-e95df2d896d7'::uuid,'ab3b54ad-dd34-49d9-8fbf-4eb5f045e4cb'::uuid,null,'jentra-w5-load-449-20261008','w5_load_20261008'),
 ('load-450','a6e2c988-a904-47ad-8640-eebeb4b313b3'::uuid,'41c374b5-25a2-4ef6-877a-ee91bfd57b35'::uuid,'b745c096-4ed2-4999-827b-ca5813b27a2d'::uuid,null,'jentra-w5-load-450-20261008','w5_load_20261008'),
 ('load-451','7db54ecc-d27a-4dd9-82b6-a73400f7b750'::uuid,'a7a60400-875c-4296-86ed-0e6074f79067'::uuid,'8c4d28ee-90ba-433d-89d5-adc7ef29f962'::uuid,null,'jentra-w5-load-451-20261008','w5_load_20261008'),
 ('load-452','e6a48e36-6c71-4e67-8b1b-4c003893c293'::uuid,'41b2916a-7651-4d82-89b7-d6f22f44859d'::uuid,'e8c40f89-5f9e-497d-8184-9fcaf3c8f311'::uuid,null,'jentra-w5-load-452-20261008','w5_load_20261008'),
 ('load-453','f14d7510-89e6-435f-8bed-369d871830ce'::uuid,'2f80a691-73f5-4d7f-8a45-746e90ef5470'::uuid,'492e32b6-c1c2-4046-81dc-ba1e7e2d6184'::uuid,null,'jentra-w5-load-453-20261008','w5_load_20261008'),
 ('load-454','6defeed4-41b6-44c1-89da-d0ed54a9c0f6'::uuid,'638ded6f-ee89-4299-8187-c8953ec6f7e8'::uuid,'fb287ab8-fcac-41e1-820d-b73dcdbe0c38'::uuid,null,'jentra-w5-load-454-20261008','w5_load_20261008'),
 ('load-455','317da6d8-7cb7-4b4d-8d23-dd3016895594'::uuid,'e1160371-4fc0-4479-8d3d-63d2c6c0e7e4'::uuid,'98749df9-d5e9-4f9c-8f3d-9fdc64484272'::uuid,null,'jentra-w5-load-455-20261008','w5_load_20261008'),
 ('load-456','85841b12-3729-44bb-8886-c735c8017363'::uuid,'868fecd1-e9cc-43b8-80b6-9632bad10a0c'::uuid,'fe781230-654a-40cd-871e-a7014532b80c'::uuid,null,'jentra-w5-load-456-20261008','w5_load_20261008'),
 ('load-457','dcb97f3d-e4b4-4c54-86e1-946690762242'::uuid,'e85d2a15-eeee-4303-8480-e7e0c2023acd'::uuid,'8c51ed46-5a93-4543-8829-e5af599a8c26'::uuid,null,'jentra-w5-load-457-20261008','w5_load_20261008'),
 ('load-458','75cca57e-efdc-4489-8ece-b07b57b8cd13'::uuid,'21d158f1-d8df-4b53-823e-70f2f46c4e59'::uuid,'c6f8891b-c5d3-43c7-8af2-1198bd76eac5'::uuid,null,'jentra-w5-load-458-20261008','w5_load_20261008'),
 ('load-459','0e0318c7-1af2-4959-8917-5d89f101cbb1'::uuid,'6f3b7f73-e5c5-456d-802e-1aa5bdcae11c'::uuid,'751bb498-5da4-433e-8fee-f6efb6976500'::uuid,null,'jentra-w5-load-459-20261008','w5_load_20261008'),
 ('load-460','240cd482-66e5-4fd4-8e47-8de0c640d818'::uuid,'757e517b-043b-4ba3-8e06-b836c445674b'::uuid,'e49ff873-9ff4-4df3-891e-10d319569e26'::uuid,null,'jentra-w5-load-460-20261008','w5_load_20261008'),
 ('load-461','2f97a483-6100-4eb8-83cf-d58907269f4b'::uuid,'25a2c859-d731-453f-8bf6-2ae89226972b'::uuid,'15c5550c-5e89-49ad-83bb-c24d46fd17a6'::uuid,null,'jentra-w5-load-461-20261008','w5_load_20261008'),
 ('load-462','d298a512-cf60-4a14-8500-c500e6844d9e'::uuid,'1c004bdf-89ef-498f-8e67-63bf5ddcd961'::uuid,'25d52b1a-e02e-49c1-8ad6-0b9ba3440528'::uuid,null,'jentra-w5-load-462-20261008','w5_load_20261008'),
 ('load-463','c0a541b3-03af-4dc3-8e87-86bd378a299c'::uuid,'fbfd8fbb-255d-460a-8ef3-b0c53810b47e'::uuid,'6fa1d483-9e96-408b-83ad-59ca35550875'::uuid,null,'jentra-w5-load-463-20261008','w5_load_20261008'),
 ('load-464','cbcfe330-3b3a-4738-8720-f39c3a88692d'::uuid,'5b7cb035-ccb8-4734-811c-aabd70e796f0'::uuid,'efc62054-18d6-486e-8da9-99731715d0d8'::uuid,null,'jentra-w5-load-464-20261008','w5_load_20261008'),
 ('load-465','938ce75a-0dd5-4cf4-8c60-ef2f281c07b4'::uuid,'0ed9dc46-6a37-4b6e-8d0b-d641cd8a2c1c'::uuid,'31b18535-4691-4d7d-87c1-6e12f21bbf9a'::uuid,null,'jentra-w5-load-465-20261008','w5_load_20261008'),
 ('load-466','feb5c1de-b7fc-4deb-8143-7f129e9ffb01'::uuid,'d3be0f17-409c-44eb-8133-5ffa34238096'::uuid,'92d17a34-d704-48c2-85f0-e450af2e8728'::uuid,null,'jentra-w5-load-466-20261008','w5_load_20261008'),
 ('load-467','86e1ecbb-f4b4-48bd-8e42-8e3782eee4d0'::uuid,'502b055a-e2bb-43f0-8eff-2467a352b08f'::uuid,'fef7a8d6-5d53-48af-872c-6a0af031f58f'::uuid,null,'jentra-w5-load-467-20261008','w5_load_20261008'),
 ('load-468','b1eca120-085a-42da-8e47-a79f4ac6b45f'::uuid,'325ff34b-801a-4dc1-8849-c8c366722a8f'::uuid,'31b82a64-788e-4f64-8820-c9d9e81b3df6'::uuid,null,'jentra-w5-load-468-20261008','w5_load_20261008'),
 ('load-469','405200c0-7556-431a-8c4e-cc819f093210'::uuid,'a816928d-7ee9-4971-832f-1db3d0f51e7f'::uuid,'08e496c2-b884-4306-8e3d-7c9ca2e4f4a5'::uuid,null,'jentra-w5-load-469-20261008','w5_load_20261008'),
 ('load-470','64bdd06a-5fb7-4a2b-82b1-b2347d515209'::uuid,'e3ef0e8a-2d62-4969-8a65-dec0a80fa69e'::uuid,'a6279226-ec2c-49c4-8a83-bce58f3d9679'::uuid,null,'jentra-w5-load-470-20261008','w5_load_20261008'),
 ('load-471','c3ecd871-9d41-4d4a-8720-80eb19aaf324'::uuid,'e5d49e7c-65ca-4b90-868a-eed69e1eda47'::uuid,'03a413b2-eed8-4ead-881f-7caae54ac1c8'::uuid,null,'jentra-w5-load-471-20261008','w5_load_20261008'),
 ('load-472','0559c9a6-520f-4e57-84c4-b9e3c4581ef2'::uuid,'db9ec906-f48f-426c-8d69-3faf6bfc9e28'::uuid,'b03ff7c5-b704-4e51-8e9d-006c3c05a029'::uuid,null,'jentra-w5-load-472-20261008','w5_load_20261008'),
 ('load-473','a9279528-c43f-43d4-8299-909cbcbaf82b'::uuid,'e2df063a-ef39-4200-86a1-d8f67c2a1be3'::uuid,'14c9e916-166f-4d94-8793-801e565e639f'::uuid,null,'jentra-w5-load-473-20261008','w5_load_20261008'),
 ('load-474','b5eeaa9f-dafb-4617-8557-6b54b7c42b36'::uuid,'fb4f3201-9128-43ce-841b-dc5bd213b24d'::uuid,'f3c507dd-9c9b-4445-8505-408c333c540e'::uuid,null,'jentra-w5-load-474-20261008','w5_load_20261008'),
 ('load-475','2ed4ff88-cf01-48af-8998-4dbbb022506e'::uuid,'82dc783e-aeb3-4ea0-8964-8ced5d2c1ae5'::uuid,'f38ad2ba-f4b1-4740-8fcd-395fd3e8691b'::uuid,null,'jentra-w5-load-475-20261008','w5_load_20261008'),
 ('load-476','3eebe7ec-2d9b-489e-8df6-657c1961bce7'::uuid,'62659b40-a891-48cd-8c27-801eaa6f83d3'::uuid,'da5593fd-d0b6-449b-805e-807c420dcfee'::uuid,null,'jentra-w5-load-476-20261008','w5_load_20261008'),
 ('load-477','51c219c3-0238-4c39-8232-48eedaaea0d4'::uuid,'6fc55760-359f-4a27-83c4-c6c47521e695'::uuid,'ed801ec9-ba23-434d-8d15-162559c87d39'::uuid,null,'jentra-w5-load-477-20261008','w5_load_20261008'),
 ('load-478','969e42a0-9bc1-4a46-8b13-232aeb5bb463'::uuid,'954e7c75-019c-468e-85d5-e5d05efee571'::uuid,'329bbd1b-0034-4e35-813d-e138c570db4f'::uuid,null,'jentra-w5-load-478-20261008','w5_load_20261008'),
 ('load-479','4f5d5e98-2357-4f15-8646-f12f20119309'::uuid,'4c9967bf-6281-479b-8b1c-823ac5e88ee3'::uuid,'a87ca914-e084-40a7-822f-465858e2b125'::uuid,null,'jentra-w5-load-479-20261008','w5_load_20261008'),
 ('load-480','4dfc0929-4978-4d65-8e90-ef6c62cad436'::uuid,'f86772d2-dadd-4d58-849d-64ac30670cf5'::uuid,'34a960cc-ec67-429b-8f6f-dd078e9bbb61'::uuid,null,'jentra-w5-load-480-20261008','w5_load_20261008'),
 ('load-481','5125ca21-98ca-48f5-899f-8b928ca6f091'::uuid,'f90b4328-c349-4e0b-8e49-e842e77d21d9'::uuid,'712ba1fc-6bc0-49b5-8b53-6108caf26a17'::uuid,null,'jentra-w5-load-481-20261008','w5_load_20261008'),
 ('load-482','bb4d1163-28f3-4e70-83a3-6331a6168f65'::uuid,'f7179d03-3194-4a4f-87a0-e59bd4f04320'::uuid,'5183d4e1-2846-4eb0-8722-98ef4f118df2'::uuid,null,'jentra-w5-load-482-20261008','w5_load_20261008'),
 ('load-483','c6704509-6c51-45e1-820a-5c9905cfcdd1'::uuid,'2fc6df16-6639-4b86-8cd9-e46c974ea859'::uuid,'345a0f8b-1567-4ae9-8c84-c8453d6c20f4'::uuid,null,'jentra-w5-load-483-20261008','w5_load_20261008'),
 ('load-484','465210cc-e716-48f4-84e9-79740566f77f'::uuid,'fdaff6c0-9f97-46b5-8568-e509753b335f'::uuid,'abc44f79-9f50-4a9f-8bcc-5fffc9000856'::uuid,null,'jentra-w5-load-484-20261008','w5_load_20261008'),
 ('load-485','eb5914e5-5d0f-4fad-8247-8d79bedaa3ba'::uuid,'996c79e2-c548-4003-84c7-47f9210e3819'::uuid,'e03a9774-2416-4127-8426-81687a6ddcba'::uuid,null,'jentra-w5-load-485-20261008','w5_load_20261008'),
 ('load-486','dceead08-5003-49d4-8d44-70a725cf7f9b'::uuid,'b5a565d6-2c75-4ed5-84d3-7f591e3a3b71'::uuid,'dc4baf8d-f452-40bb-8a5d-d9d0309445bc'::uuid,null,'jentra-w5-load-486-20261008','w5_load_20261008'),
 ('load-487','9a647e15-10c4-4680-8ebf-8347f1b5fe35'::uuid,'0bcd85c9-9f4f-4027-86be-df23cf24ec72'::uuid,'5d8ca522-f2b5-496a-8732-6d339ce1e526'::uuid,null,'jentra-w5-load-487-20261008','w5_load_20261008'),
 ('load-488','5bef0e7a-0eca-4eac-8f6d-c87a46b1ddc2'::uuid,'6d3b86c4-5453-42f5-8368-20b32d057b01'::uuid,'26961ba2-b23d-48c3-866f-42923868b856'::uuid,null,'jentra-w5-load-488-20261008','w5_load_20261008'),
 ('load-489','e5cc18a4-2a0b-4234-8327-5cfa2e83d416'::uuid,'f1618227-3da2-4971-84ad-c1a9a84063ff'::uuid,'93c43759-9d8a-4b8e-8512-92a7ec959515'::uuid,null,'jentra-w5-load-489-20261008','w5_load_20261008'),
 ('load-490','d3565966-a072-43b9-8ea4-e5f887839830'::uuid,'6c36b2e2-3f03-474d-80ea-4cbb9808220d'::uuid,'e9a7f887-aae5-4fb4-80a7-fc1f5ce674af'::uuid,null,'jentra-w5-load-490-20261008','w5_load_20261008'),
 ('load-491','86e3d76b-0073-4956-84e8-e5e6d2e26288'::uuid,'96c1b88c-60ef-4f46-8bd6-7b5d20d706fe'::uuid,'8caf2d31-f9c3-4e77-89ea-0ae0a78f27da'::uuid,null,'jentra-w5-load-491-20261008','w5_load_20261008'),
 ('load-492','fbcb11bf-bff0-432a-89e1-26f0c2689adb'::uuid,'66885171-d049-45a2-83b7-38fc0e4e80d5'::uuid,'d4cde277-399d-4d4c-8d6f-aea2f5435cfa'::uuid,null,'jentra-w5-load-492-20261008','w5_load_20261008'),
 ('load-493','c88bcf7a-b720-49de-85b6-dde66e6015e0'::uuid,'a45c265a-a16d-42e4-8989-d4a6a7b39178'::uuid,'70eb13e5-e9b6-4b54-804f-a5a78830e2b3'::uuid,null,'jentra-w5-load-493-20261008','w5_load_20261008'),
 ('load-494','16fa14fa-0ad2-477c-88a2-e5e858bec250'::uuid,'5c743b5b-3c01-4225-8572-64456d54b3b8'::uuid,'38812229-23b6-4737-8cfd-da57c2d89e3e'::uuid,null,'jentra-w5-load-494-20261008','w5_load_20261008'),
 ('load-495','8477935e-498d-4b80-8655-058740725522'::uuid,'f6e7a6dc-a334-45bd-8082-1b7459496b1d'::uuid,'0d9618a6-7f2a-49b1-8731-ce2864ed617b'::uuid,null,'jentra-w5-load-495-20261008','w5_load_20261008'),
 ('load-496','d156a4b7-e1de-439f-8a52-4fabcb956bc2'::uuid,'97af7221-d7bc-40e5-8b74-9495e195b502'::uuid,'0670672d-682b-4f30-8f64-39b82746d2a4'::uuid,null,'jentra-w5-load-496-20261008','w5_load_20261008'),
 ('load-497','ba344757-1a2a-4f17-88e8-d2cf71710e15'::uuid,'c95d9b1a-d7e6-43a2-858d-5333a571f67f'::uuid,'1aec199d-8185-42f8-8615-237d5c6a18c4'::uuid,null,'jentra-w5-load-497-20261008','w5_load_20261008'),
 ('load-498','1c0e12f1-2fb0-43d6-89f7-a5ea5e60a3db'::uuid,'9da0da2a-2c08-4ffa-8aab-302e51bc4801'::uuid,'1f91e008-8dda-4ca6-8866-120807715d21'::uuid,null,'jentra-w5-load-498-20261008','w5_load_20261008');
do $$begin
 if exists(select 1 from core.tenants t join w5_runtime_scopes s on t.id=s.tenant_id or t.slug=s.slug) then raise exception 'RUNTIME_TENANT_COLLISION';end if;
 if exists(select 1 from billing.plans where code in('w5_runtime_20261008','w5_load_20261008','w5_quota10_20261008','w5_foreign_20261008')) then raise exception 'RUNTIME_PLAN_COLLISION';end if;
 if exists(select 1 from intelligence_control.operators o join w5_runtime_accounts a on a.user_id=o.actor_id) then raise exception 'RUNTIME_OPERATOR_COLLISION';end if;
end$$;
insert into billing.plans(code,name,trial_days) values ('w5_runtime_20261008','Synthetic Wave 5 Runtime',7),('w5_load_20261008','Synthetic Wave 5 Load',7),('w5_quota10_20261008','Synthetic Wave 5 Quota Contention',7),('w5_foreign_20261008','Synthetic Wave 5 Foreign',7);
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit) values
 ('w5_runtime_20261008','analytics',true,null),
 ('w5_runtime_20261008','module.ai',true,null),
 ('w5_runtime_20261008','module.projects',true,null),
 ('w5_runtime_20261008','module.finance',true,null),
 ('w5_runtime_20261008','quota.ai.tokens',true,'8000'::numeric),
 ('w5_runtime_20261008','quota.webhook.deliveries',true,'100'::numeric),
 ('w5_runtime_20261008','quota.integration.commands',true,'200'::numeric);
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit) values
 ('w5_load_20261008','analytics',true,null),
 ('w5_load_20261008','quota.ai.tokens',true,'0'::numeric),
 ('w5_load_20261008','quota.webhook.deliveries',true,'0'::numeric),
 ('w5_load_20261008','quota.integration.commands',true,'0'::numeric);
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit) values
 ('w5_quota10_20261008','analytics',true,null),
 ('w5_quota10_20261008','quota.ai.tokens',true,'10'::numeric),
 ('w5_quota10_20261008','quota.webhook.deliveries',true,'10'::numeric),
 ('w5_quota10_20261008','quota.integration.commands',true,'10'::numeric);
insert into billing.plan_entitlements(plan_code,entitlement_code,enabled,numeric_limit) values
 ('w5_foreign_20261008','analytics',true,null),
 ('w5_foreign_20261008','quota.ai.tokens',true,'0'::numeric),
 ('w5_foreign_20261008','quota.webhook.deliveries',true,'0'::numeric),
 ('w5_foreign_20261008','quota.integration.commands',true,'0'::numeric);
insert into core.tenants(id,name,slug,status,timezone,default_currency_code,created_by)
 select tenant_id,'Synthetic Wave 5 '||key,slug,'trial','Asia/Colombo','LKR',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes;
insert into core.legal_entities(id,tenant_id,name,code,currency_code,timezone,rounding_scale,created_by)
 select entity_id,tenant_id,'Synthetic '||key,case key when 'runtime' then 'W5RT' when 'foreign' then 'W5FX' else 'W5LOAD' end,'LKR','Asia/Colombo',6,
 (select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes;
insert into core.branches(id,tenant_id,legal_entity_id,name,code,created_by)
 select branch_id,tenant_id,entity_id,'Synthetic RT1','RT1',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes
 union all select second_branch_id,tenant_id,entity_id,'Synthetic RT2 denial branch','RT2',(select user_id from w5_runtime_accounts where label='billing-admin') from w5_runtime_scopes where second_branch_id is not null;
insert into billing.tenant_subscriptions(id,tenant_id,plan_code,status,seats,trial_started_at,trial_ends_at,current_period_ends_at)
 select md5(tenant_id::text||':subscription')::uuid,tenant_id,plan_code,'trialing',case key when 'runtime' then 5 when 'foreign' then 1 else 4 end,
 statement_timestamp(),statement_timestamp()+interval '7 days',null from w5_runtime_scopes;
insert into core.memberships(id,tenant_id,user_id,status,joined_at)
 select md5(s.tenant_id::text||':'||a.label||':member')::uuid,s.tenant_id,a.user_id,'active',statement_timestamp()
 from w5_runtime_scopes s cross join w5_runtime_accounts a
 where (s.key='foreign' and a.label='foreign-member') or (s.key<>'foreign' and a.label in('proposer','approver','executor','billing-admin'));
create temporary table w5_runtime_roles(tenant_id uuid,role_key text,role_id uuid,permissions jsonb,requires_mfa boolean,primary key(tenant_id,role_key));
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'reader','a6caca89-dca5-4f8e-8671-f49bf029bed4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view","finance.view","finance.receivables.view","sales.returns.view","procurement.bills.view","people.view","people.payroll.view","projects.view","projects.cost.view","ai.proposals.view","analytics.reports.view"]'::jsonb,false);
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'financeAnchor','09ae67a2-4015-4e78-8c25-100a8a26129a'::uuid,'["finance.view","finance.reports.export"]'::jsonb,false);
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'proposer','cc9c035c-74d4-46ac-8fdb-879f9d95aebf'::uuid,'["ai.proposals.manage","analytics.reports.manage","analytics.cash_dates.prepare","integrations.manage","finance.reports.export"]'::jsonb,false);
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'approver','d57947df-f429-419a-89f8-3d8f5db5fe2b'::uuid,'["ai.proposals.approve","analytics.cash_dates.approve","finance.classifications.approve"]'::jsonb,true);
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'executor','d8ecedb2-0e98-4fbf-8416-d908b0ec039c'::uuid,'["ai.proposals.execute"]'::jsonb,true);
insert into w5_runtime_roles values('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'billing','a7030e01-7d49-4db9-8f87-00ffe3fe58b9'::uuid,'["billing.read","billing.synthetic.manage","core.members.invite"]'::jsonb,true);
insert into w5_runtime_roles values('c1ae4d89-6379-45ef-8ee8-1779593eb8d9'::uuid,'foreignReader','ad1f757f-9aa5-4d53-80f4-b7b5bd78832e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b619cd7-adde-4c04-8526-f1170a32a25a'::uuid,'loadReader','4bed7d2b-5c20-4f88-833e-2017b710d790'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b619cd7-adde-4c04-8526-f1170a32a25a'::uuid,'billing','2e2f5c9a-dc11-4d4a-84e9-1521f0698027'::uuid,'["billing.read","billing.synthetic.manage","core.members.invite"]'::jsonb,true);
insert into w5_runtime_roles values('3d63eec9-3672-460a-8927-6aa4217b81a1'::uuid,'loadReader','68533c22-d3ad-44be-8c2b-ccafb0e497d6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3d63eec9-3672-460a-8927-6aa4217b81a1'::uuid,'loadBilling','9635d96b-f502-4e0e-8736-d5026c45281a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bad6b00f-7d96-4918-8870-00ce7f51ef86'::uuid,'loadReader','af22e8e4-b541-484a-8ed9-256593e97f38'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bad6b00f-7d96-4918-8870-00ce7f51ef86'::uuid,'loadBilling','f4049e50-fffc-428d-86a8-b7c809630b77'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('799e67c7-faa4-44fb-8c4e-29973a7fefc1'::uuid,'loadReader','4260ac98-917c-4cba-8496-1a6a0d627172'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('799e67c7-faa4-44fb-8c4e-29973a7fefc1'::uuid,'loadBilling','0ab88bd8-baa7-48ba-83ce-8c706c2d73f4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f1076664-74fd-4972-85b6-6b246897c39e'::uuid,'loadReader','b153b995-23b2-4c70-85c8-756110d84549'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f1076664-74fd-4972-85b6-6b246897c39e'::uuid,'loadBilling','2f7ca6ad-0ea8-4cf7-8cb7-c652076a6b5b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7cef392b-990d-41eb-8283-4158144bb1a6'::uuid,'loadReader','7398f848-c151-4def-8886-49eca4bb6798'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7cef392b-990d-41eb-8283-4158144bb1a6'::uuid,'loadBilling','fe4a6834-ebc4-4c1c-85a3-92d9589eded9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fd27109c-dbc6-46d9-8a30-b3ac9cffefb6'::uuid,'loadReader','e53c0e8b-ccdd-4ae1-8bef-10b668e54835'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fd27109c-dbc6-46d9-8a30-b3ac9cffefb6'::uuid,'loadBilling','30010061-4198-45c2-8c7a-978ff644ea8c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c2eaf879-3a6c-4136-8a65-8906e3b69aaf'::uuid,'loadReader','e4d52561-4875-4563-8d7d-6210e7ff3aed'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c2eaf879-3a6c-4136-8a65-8906e3b69aaf'::uuid,'loadBilling','59825e42-7c5b-4226-8fca-d6bc53c3f648'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b3def46f-e903-4aa4-84eb-d16fdc8a48f6'::uuid,'loadReader','8c553b34-f531-44a9-80f1-8031e523662b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b3def46f-e903-4aa4-84eb-d16fdc8a48f6'::uuid,'loadBilling','efdbbd61-73c3-4775-8cfb-5df832762816'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7a5fdc78-16ee-40c9-81bf-ec5e822dc6e8'::uuid,'loadReader','09a1099d-e622-4496-8946-b3e5737dbb7c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7a5fdc78-16ee-40c9-81bf-ec5e822dc6e8'::uuid,'loadBilling','6d9b0ff4-23f9-4cd8-8f7a-1c62e0b56f0d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('193b8936-a775-4e27-88bb-e277339c99c0'::uuid,'loadReader','28109eb3-9263-4e04-8a47-f4fc523cb445'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('193b8936-a775-4e27-88bb-e277339c99c0'::uuid,'loadBilling','4465a361-e477-413c-8f52-5a0e067b0036'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('765a971d-f59e-4326-8332-088d8af6263f'::uuid,'loadReader','2838f1e7-ba40-4556-8240-1ece1609d9e5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('765a971d-f59e-4326-8332-088d8af6263f'::uuid,'loadBilling','0cc582fb-abac-49c1-8ef0-71c7016bf734'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('af36525b-3909-4cb3-894d-8a93506b0260'::uuid,'loadReader','dea0882b-ba49-48ea-830f-568e53004854'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('af36525b-3909-4cb3-894d-8a93506b0260'::uuid,'loadBilling','338ca6f1-93a7-41ef-8bed-cc5afbb6578d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ac5d6aee-27e0-4eef-8771-17bfba7e9ec2'::uuid,'loadReader','e7447665-c3a7-498b-8ae6-47309827987b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ac5d6aee-27e0-4eef-8771-17bfba7e9ec2'::uuid,'loadBilling','2711d48d-9170-490f-8ccb-cc9f30092108'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('73c0c2c4-5b84-4237-8eda-cf63c9531e01'::uuid,'loadReader','f4428c68-93a8-497c-8504-f732377ba19e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('73c0c2c4-5b84-4237-8eda-cf63c9531e01'::uuid,'loadBilling','2bc78203-93f9-4e36-8165-401c7eba8ca3'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('94aeb3fe-8170-4d14-8871-63b2a92cd047'::uuid,'loadReader','0c517302-82c6-4900-80d3-37130228cb60'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('94aeb3fe-8170-4d14-8871-63b2a92cd047'::uuid,'loadBilling','33fdd8de-c7b3-4034-8e70-482628fe810f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1d4439e5-2c50-47ba-82ae-bb30bf43ae80'::uuid,'loadReader','5f0f09f3-d22a-400d-8b92-fd13f2f14266'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1d4439e5-2c50-47ba-82ae-bb30bf43ae80'::uuid,'loadBilling','046d48e5-35b8-473b-890e-6487f6f8f780'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0318b048-be76-47d9-842c-a287251ff27d'::uuid,'loadReader','cd4d665a-a3e4-43f2-8b5a-92c8cbacdc2d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0318b048-be76-47d9-842c-a287251ff27d'::uuid,'loadBilling','7db82a39-4eed-4daf-851b-13212bd24a38'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d07c6612-a7fd-4f06-8629-ae202c6ed8e2'::uuid,'loadReader','ec911bda-41ed-4164-8384-3ea400491a83'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d07c6612-a7fd-4f06-8629-ae202c6ed8e2'::uuid,'loadBilling','26f6b9fe-13b3-430e-8eb4-b8d93d1ad35b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('39c1cfa0-7b12-4b61-8ac6-f21d011f088d'::uuid,'loadReader','a31e507f-b498-4404-82d5-1048b0d22a04'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('39c1cfa0-7b12-4b61-8ac6-f21d011f088d'::uuid,'loadBilling','9ba64951-b483-4097-8219-8f517d9e0f23'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('39d45a2f-bc2a-4b14-82b7-4d77c8256b42'::uuid,'loadReader','6999a77f-b42f-43b2-8549-8dd9959e8fff'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('39d45a2f-bc2a-4b14-82b7-4d77c8256b42'::uuid,'loadBilling','19e40098-99ae-4d20-85ef-28c669c4c240'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4b2b7361-8492-4a69-856b-95aa4b41f275'::uuid,'loadReader','c37d2e15-6673-44c8-82b0-4a72345fad68'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b2b7361-8492-4a69-856b-95aa4b41f275'::uuid,'loadBilling','cbd6fa39-daf6-462d-87c4-8d393f2ce54d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6ec05bf5-56db-427e-8b81-e81aab5d1bf4'::uuid,'loadReader','70a66041-f40e-43d0-829a-d6cae12e96d0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6ec05bf5-56db-427e-8b81-e81aab5d1bf4'::uuid,'loadBilling','039d42dd-9b5c-41fa-8110-39a0abbfdab4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('33c091d5-01fa-41d6-8058-43bc6242a804'::uuid,'loadReader','bfe24ace-6e4c-4606-8fc8-6b4a13e93fc5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('33c091d5-01fa-41d6-8058-43bc6242a804'::uuid,'loadBilling','3bf70bc1-3be8-4fec-85a1-155373ab8c95'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f732e7bb-5f16-4ece-8abe-608bceccbc44'::uuid,'loadReader','859fd0b6-4971-4c80-8a06-3cfacf9fff98'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f732e7bb-5f16-4ece-8abe-608bceccbc44'::uuid,'loadBilling','46206e66-90d3-427b-8209-1f1d439eee14'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('04d9c5b2-085e-4de8-824c-dcb7e88b7a3f'::uuid,'loadReader','5d475415-044e-4a83-811f-a9080ef6e555'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('04d9c5b2-085e-4de8-824c-dcb7e88b7a3f'::uuid,'loadBilling','cfe9069f-7e13-42e9-8c89-badb606a99fb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('982e2e32-bc0e-4de9-8c43-282dbcc8e5f0'::uuid,'loadReader','693c3e21-c3d4-4fb1-8cd2-271dc21bc6ab'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('982e2e32-bc0e-4de9-8c43-282dbcc8e5f0'::uuid,'loadBilling','623a7838-6be4-4637-8fa5-b71c90073a47'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0a2860ae-b66d-4948-87af-701c8de72463'::uuid,'loadReader','272be685-5f4e-44f1-8db1-af8b8f073918'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0a2860ae-b66d-4948-87af-701c8de72463'::uuid,'loadBilling','db002be1-ae8c-4216-8c74-3c3512544ce8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('73109a1f-2a7c-4716-8387-941887ce08d7'::uuid,'loadReader','b2d660f6-fc47-47f0-82af-0575035186e1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('73109a1f-2a7c-4716-8387-941887ce08d7'::uuid,'loadBilling','2672a9c6-4332-418d-83b9-5b9609048d15'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8baa147b-ff61-460d-865f-19edf11aae03'::uuid,'loadReader','65680fa8-984f-49c6-827a-a1040d263a5e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8baa147b-ff61-460d-865f-19edf11aae03'::uuid,'loadBilling','170e1c27-8308-400c-8fd9-72b1681be4c0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('39ae6862-dc18-4503-8fc0-1bc2f32c9327'::uuid,'loadReader','7033946d-c2f1-4893-8343-cd3d0ea2b525'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('39ae6862-dc18-4503-8fc0-1bc2f32c9327'::uuid,'loadBilling','14539f1e-a9fb-4406-876b-1934203f3003'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8a0595a2-abe9-4818-8d55-1d03e47b167a'::uuid,'loadReader','75d1f2bc-1d2e-4ede-8715-56ff3efd7d1e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8a0595a2-abe9-4818-8d55-1d03e47b167a'::uuid,'loadBilling','caae467a-3ade-4256-8251-87f688196146'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('60990906-5c37-4bb9-85ed-64fd3f93a60f'::uuid,'loadReader','1f7240a4-9a90-414a-8178-9c794c1cc248'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('60990906-5c37-4bb9-85ed-64fd3f93a60f'::uuid,'loadBilling','25bf837b-ac2d-4d20-829c-3161d7c925e9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8009fd88-3126-4981-87e2-1e4bda8efb7c'::uuid,'loadReader','efde99c0-21ba-436c-81c5-99d91bb6bd42'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8009fd88-3126-4981-87e2-1e4bda8efb7c'::uuid,'loadBilling','02249ffe-4439-4321-8ab0-135e05db63bf'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ce8a7b34-2c24-41c4-8ed3-0b38a8b8995c'::uuid,'loadReader','e22b97e5-7e27-41c1-8b97-ed4e849f0489'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ce8a7b34-2c24-41c4-8ed3-0b38a8b8995c'::uuid,'loadBilling','8d5f8b2b-f293-46cc-8ca4-f2efed21c2fe'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('83233d64-40b3-4ae4-8092-c8fcc36ed720'::uuid,'loadReader','284b0d78-a700-40d7-8842-5c0832320c4a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('83233d64-40b3-4ae4-8092-c8fcc36ed720'::uuid,'loadBilling','c1bcb3fb-3a00-4df6-8fe8-329cf4b06182'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('71500d94-4e44-47c6-8d8d-587486726371'::uuid,'loadReader','6ed2a33b-304c-4760-851a-da2da7cf4269'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('71500d94-4e44-47c6-8d8d-587486726371'::uuid,'loadBilling','3a05b1c4-f8fc-4926-8eb1-9feccd4c491d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b5799ef0-b2d3-444f-8317-e59e99ca5b15'::uuid,'loadReader','c1da95b6-ee4d-4850-85e0-24c433bff188'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b5799ef0-b2d3-444f-8317-e59e99ca5b15'::uuid,'loadBilling','9d5a55cc-0115-4f04-8e3c-99da9a058851'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f3125611-bf63-4f6d-827c-88c185e425ec'::uuid,'loadReader','4b3bcd73-7f03-41f4-8608-996393bbee13'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f3125611-bf63-4f6d-827c-88c185e425ec'::uuid,'loadBilling','0d42f888-fa2d-4e2e-84f0-a5493317d278'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e717f828-938e-4460-8155-b582ddc83985'::uuid,'loadReader','34799737-4647-45bf-87ae-7046d644f431'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e717f828-938e-4460-8155-b582ddc83985'::uuid,'loadBilling','6bb27c23-9c06-41db-8ac4-8cb1e18d900c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2135a1a1-f613-4b07-887a-c89ed3dfe3c9'::uuid,'loadReader','4172f27c-1c88-4ca7-8e1b-296c5092021e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2135a1a1-f613-4b07-887a-c89ed3dfe3c9'::uuid,'loadBilling','4fd44983-be29-4de9-8d3b-2dcc6b143bec'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('235daf1b-45ce-4008-830d-16eed127884c'::uuid,'loadReader','bb1eb24f-9691-407c-8958-d13b7dc8fe54'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('235daf1b-45ce-4008-830d-16eed127884c'::uuid,'loadBilling','7f71fa9f-38be-4a1c-87a9-4461e3956b25'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d599aa1b-94a3-4e5a-8de6-1db94a1acb85'::uuid,'loadReader','f4bd0b47-4490-48da-875a-f95a84921f6b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d599aa1b-94a3-4e5a-8de6-1db94a1acb85'::uuid,'loadBilling','24618e18-255c-4260-8dc7-a6400bf0a882'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c2a1821a-1bd8-4784-8af2-cbae97fc98d5'::uuid,'loadReader','c6eb9bbc-7b61-43a4-8b27-585a32df66ba'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c2a1821a-1bd8-4784-8af2-cbae97fc98d5'::uuid,'loadBilling','b5683e12-0cc3-4ad5-854d-2af1ea241ff6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e086594c-0d93-47f2-808f-99c2efad69c1'::uuid,'loadReader','4a2e9fa9-e2c8-4be9-84bf-748bdf24f6ab'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e086594c-0d93-47f2-808f-99c2efad69c1'::uuid,'loadBilling','81cad536-0a96-4ebb-87f3-33c73dc0f9f0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fa80a45a-9c67-452f-8332-7e066c3a409b'::uuid,'loadReader','f273db69-33f3-4e61-81b1-b2971b411a35'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fa80a45a-9c67-452f-8332-7e066c3a409b'::uuid,'loadBilling','9c7de8f4-1232-43d0-8ad2-579ffb5bd74e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('730df1ce-adbd-4657-8488-4d0e3d10d94f'::uuid,'loadReader','21d6b2f5-639d-4d73-81a2-af3de6aa1f98'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('730df1ce-adbd-4657-8488-4d0e3d10d94f'::uuid,'loadBilling','5b75e7ef-7f02-42ee-8c41-2e18f62da9f5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9dc7b7fe-999a-4fd8-87ae-fd1e464997f6'::uuid,'loadReader','036f78f2-c217-4b73-8a42-2252468d2e14'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9dc7b7fe-999a-4fd8-87ae-fd1e464997f6'::uuid,'loadBilling','37724d6c-bab1-489f-8411-5c6d198750e6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('89c60c6a-6c39-4f79-8f04-9f414febda7e'::uuid,'loadReader','05ed7e8f-1844-4a04-815a-807d9b55e72d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('89c60c6a-6c39-4f79-8f04-9f414febda7e'::uuid,'loadBilling','d3520a55-61b4-4f4f-8671-4bbe738b3ed6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('119bdced-7889-4ac9-80a4-f1d030164ff2'::uuid,'loadReader','312560ca-17ba-4d94-85ac-8de2e91ce539'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('119bdced-7889-4ac9-80a4-f1d030164ff2'::uuid,'loadBilling','a9478c2e-f1a9-497d-83aa-a28646046a67'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f4294705-e4c5-447b-84fa-fd63863a57b0'::uuid,'loadReader','137bc41f-5677-4255-8c36-20302956d92a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f4294705-e4c5-447b-84fa-fd63863a57b0'::uuid,'loadBilling','9ef584b5-f2ce-4027-8b94-a83ed038b71f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('14f843cc-bf3e-496a-81d9-d80af5b11df9'::uuid,'loadReader','a3219da6-a286-4440-887a-a09d51e637ae'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('14f843cc-bf3e-496a-81d9-d80af5b11df9'::uuid,'loadBilling','993231e6-ef3b-492e-8c3c-8d9dcd65be5e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5760dec8-ee4c-45bf-8164-a58cc118789f'::uuid,'loadReader','9d38fb14-e703-4abe-85d6-3eea984e5d67'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5760dec8-ee4c-45bf-8164-a58cc118789f'::uuid,'loadBilling','ccc68e56-210e-465c-804f-7e6fe9c0a469'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('89b6d90f-63bf-4163-841d-1c03771328fe'::uuid,'loadReader','1b189d59-b296-477e-8196-a3cb9f51c04d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('89b6d90f-63bf-4163-841d-1c03771328fe'::uuid,'loadBilling','15e8630b-bd21-4928-81d9-9e0d61d66083'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2e3abc10-b992-4a6d-8ee5-c3cd70857cd1'::uuid,'loadReader','28e08085-f866-4395-83c4-04be5f2edf11'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2e3abc10-b992-4a6d-8ee5-c3cd70857cd1'::uuid,'loadBilling','0ae1b0ab-4712-49b7-847a-03ac1933d64d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b5a5e0ac-2fb0-4288-83ea-65c102269aed'::uuid,'loadReader','44bf20d9-cf60-479d-8388-5019b85924c7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b5a5e0ac-2fb0-4288-83ea-65c102269aed'::uuid,'loadBilling','8e9d8422-f11e-456b-838f-48acda6f2bb7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('979f8c5d-2117-4865-83cd-d9b8e966f954'::uuid,'loadReader','93447a05-527d-4fe4-83c3-235b27a26042'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('979f8c5d-2117-4865-83cd-d9b8e966f954'::uuid,'loadBilling','41dfd271-fcee-46c9-84d7-58712043a785'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2acdcf58-ae92-4a91-8e31-bee1307153a2'::uuid,'loadReader','1066c2aa-a44e-478b-8f16-241323e1a84d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2acdcf58-ae92-4a91-8e31-bee1307153a2'::uuid,'loadBilling','3b64c757-00ff-4f32-82dc-b4cd926ee0af'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cf3f0118-18e4-4d40-8d2b-b376c166d147'::uuid,'loadReader','540b2d22-b32f-4e4c-8282-5c396bd7b23d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cf3f0118-18e4-4d40-8d2b-b376c166d147'::uuid,'loadBilling','5ad7d722-056c-4a18-8d09-a3044c2da07a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ca439c21-5e9a-4c59-8965-b129d3dfa27f'::uuid,'loadReader','79865066-e3ba-4831-83f0-9998e88053c4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ca439c21-5e9a-4c59-8965-b129d3dfa27f'::uuid,'loadBilling','a47ed9d0-76f0-4614-8877-0789501ae186'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a7ef64a4-cd3e-4055-8211-37db1133862f'::uuid,'loadReader','88093e7b-aa7e-432c-811d-253a1552ef19'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a7ef64a4-cd3e-4055-8211-37db1133862f'::uuid,'loadBilling','41fcaf3a-641b-4eb5-82e9-0b209008aaaf'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('89a55823-691b-4660-858d-b0c66cef2516'::uuid,'loadReader','3732a964-8067-49fa-839c-7d8496b805b2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('89a55823-691b-4660-858d-b0c66cef2516'::uuid,'loadBilling','4c57434f-753d-45df-8bf0-e0b871883e42'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ba85ba9c-3d9b-4b0d-8d54-5175a2fa57b0'::uuid,'loadReader','6bf2050d-18ce-478c-8c53-28afc0b123d1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ba85ba9c-3d9b-4b0d-8d54-5175a2fa57b0'::uuid,'loadBilling','47a24d3b-ce0d-4ef7-8c5d-ea92136d17c6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('afa19958-00fd-4fb5-8026-168f969c0569'::uuid,'loadReader','9b77e9ea-f11f-42d2-8eee-242c915b41bc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('afa19958-00fd-4fb5-8026-168f969c0569'::uuid,'loadBilling','8e012151-7e70-41b0-87c3-bb0d04425f50'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('21f67a70-376a-4231-89f9-5469d311c925'::uuid,'loadReader','581c1c99-5153-42a4-8a94-564c0193a4d8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('21f67a70-376a-4231-89f9-5469d311c925'::uuid,'loadBilling','ed51b15c-8b4b-4e6b-809d-c9dc88921451'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3889353d-a878-446b-88ad-9f530ce1dc00'::uuid,'loadReader','ce4b1709-9c53-4a94-86ef-074ec88e4c77'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3889353d-a878-446b-88ad-9f530ce1dc00'::uuid,'loadBilling','21ac548a-5111-4a7d-8c3b-3b92d45bea04'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('108537a1-6d20-4b4b-8ac0-8994d357a346'::uuid,'loadReader','3363555e-0bc5-4f11-803f-c96130100d28'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('108537a1-6d20-4b4b-8ac0-8994d357a346'::uuid,'loadBilling','ec312405-d55e-4d23-8df4-fafccebf3da1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d262ad53-6f25-4e09-8a3e-5965d897fb2a'::uuid,'loadReader','e6b23b1c-8710-440c-854c-9af4f7899ff9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d262ad53-6f25-4e09-8a3e-5965d897fb2a'::uuid,'loadBilling','60795dbb-5422-4552-8840-13bafd58465f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7849fb98-c6a3-4ac2-86ef-dfe190fc5cc2'::uuid,'loadReader','e5f19803-dca8-467c-8c97-76ede093d46f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7849fb98-c6a3-4ac2-86ef-dfe190fc5cc2'::uuid,'loadBilling','38f05f2f-658d-44ef-81de-783bdb676741'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('19a9fe42-74a2-4c9f-87ff-f40bc621bcb1'::uuid,'loadReader','a3426fa5-723e-48e2-8c00-319da957f368'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('19a9fe42-74a2-4c9f-87ff-f40bc621bcb1'::uuid,'loadBilling','783aabd6-d50e-494b-8429-0d7d1fa10135'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5369bf49-2489-42a5-8b2d-c09f856de9ec'::uuid,'loadReader','38ac012b-556d-434e-8f80-9d55bff9e90b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5369bf49-2489-42a5-8b2d-c09f856de9ec'::uuid,'loadBilling','eeeb267e-d8a2-4a92-87e1-1058f5a35c5b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c774f43e-7c62-4767-83e6-fa39ee7d8d47'::uuid,'loadReader','f3f7d38a-cc49-4309-89b5-6a3c0c8c644c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c774f43e-7c62-4767-83e6-fa39ee7d8d47'::uuid,'loadBilling','3a17fe4e-bf48-45cb-8e40-076696988e1e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1a08deed-969a-46f6-8839-67af79a47b6c'::uuid,'loadReader','fa313d8f-37ba-41a4-8172-09db6a365b2b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1a08deed-969a-46f6-8839-67af79a47b6c'::uuid,'loadBilling','6e95715a-5308-4c59-8165-e527b814723b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('734ad325-3274-4b7e-8252-720d8e4bd8a5'::uuid,'loadReader','833ea856-2513-43f3-81ff-418a7e97dbf5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('734ad325-3274-4b7e-8252-720d8e4bd8a5'::uuid,'loadBilling','a7a6de86-fbee-4069-8ca4-fa8a8a7338e4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('12205cbf-21db-4e55-850c-454389d24397'::uuid,'loadReader','5c51d46e-fa4d-406b-8541-e2d1046b0b5c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('12205cbf-21db-4e55-850c-454389d24397'::uuid,'loadBilling','deea6610-fa2f-48f2-874d-4ff35bb40bfe'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('09db3ab4-7e88-4824-8eb7-4de2753fc2bd'::uuid,'loadReader','eb6864d6-407f-494f-8cc4-2a00221a74b3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('09db3ab4-7e88-4824-8eb7-4de2753fc2bd'::uuid,'loadBilling','f7e5e2ab-e5c9-4c56-8b1a-9abbeeee77f3'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e237e287-8b86-4f8a-8269-932c89f25d2e'::uuid,'loadReader','936de4cd-e535-475c-8e05-53176e661265'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e237e287-8b86-4f8a-8269-932c89f25d2e'::uuid,'loadBilling','4db8837a-d6b2-4dfd-8a92-150d41b540c6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('be8415db-6756-4b12-899b-d4881b5adabe'::uuid,'loadReader','68a7bf65-9f88-42a3-8b19-782030c92d2b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('be8415db-6756-4b12-899b-d4881b5adabe'::uuid,'loadBilling','705e5203-cf1a-4cb4-8219-177d23164258'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6ba39b23-4526-49f2-8f81-9dc04ab4f63a'::uuid,'loadReader','3814d073-0690-4252-88a7-84d61064c0d6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6ba39b23-4526-49f2-8f81-9dc04ab4f63a'::uuid,'loadBilling','4bdc76c3-bb1e-49be-8805-21dda1e73597'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('35833635-9de0-4527-86db-d2326f975890'::uuid,'loadReader','cd98bc17-87be-4bb3-8a00-89bd9d262ae2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('35833635-9de0-4527-86db-d2326f975890'::uuid,'loadBilling','0efc6ef6-c7fc-4a4e-8aed-670ad341aab7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('aebf89b2-d8f8-4392-897e-b2afb955e5df'::uuid,'loadReader','89f38239-ae5e-4aaa-8d2b-6443937bd0e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('aebf89b2-d8f8-4392-897e-b2afb955e5df'::uuid,'loadBilling','80034aa1-23bd-40f2-885a-d481bd85f9fd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('16596e5f-7c3d-4ff8-8a24-0c7ef85274f3'::uuid,'loadReader','a21e9fa3-b912-4d3e-8637-ebd33c9b10ae'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('16596e5f-7c3d-4ff8-8a24-0c7ef85274f3'::uuid,'loadBilling','cd33eeaa-f9ed-409e-8c4f-a170404716bf'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5ead7647-02a5-4d3e-8691-ef2c3829cbec'::uuid,'loadReader','45ca8315-9c42-418d-84c5-8d3e39ad4a15'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5ead7647-02a5-4d3e-8691-ef2c3829cbec'::uuid,'loadBilling','cf8663d7-c4ac-47db-8deb-4cf75a370c5a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('46659684-e93a-466a-84ee-e29eb0a81e26'::uuid,'loadReader','8a80ab7c-3cdf-405d-8465-fac008b43495'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('46659684-e93a-466a-84ee-e29eb0a81e26'::uuid,'loadBilling','fbd61bee-1188-4400-834f-73d346f3483a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2c7df18e-b86f-4b81-88f9-995d8c667d43'::uuid,'loadReader','aca4dc10-c7e3-4090-8154-21958a09d9ff'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2c7df18e-b86f-4b81-88f9-995d8c667d43'::uuid,'loadBilling','a569ec9e-03c7-4d8a-8527-7dd2987abe86'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a7dd6641-4f6f-4661-807f-4f83942eb29f'::uuid,'loadReader','47045cc7-4d3f-4aea-8a85-e9c8e6fab6f6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a7dd6641-4f6f-4661-807f-4f83942eb29f'::uuid,'loadBilling','43a83d83-8664-4360-8b98-bff00103ee54'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('716fa1c7-234a-4bc4-82cf-65fc59393220'::uuid,'loadReader','097f0e55-01a0-47a3-84b7-3aeaeeaf6b87'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('716fa1c7-234a-4bc4-82cf-65fc59393220'::uuid,'loadBilling','f8f67c93-2d4c-4917-89bf-75614d62a831'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5564c40b-6cdc-49a7-8a30-a441c71d9496'::uuid,'loadReader','58f1728e-90ed-4eac-87f5-c88a5eb56c0e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5564c40b-6cdc-49a7-8a30-a441c71d9496'::uuid,'loadBilling','a32abd45-c78c-4eb5-8a66-4515746b75b2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('31720aa8-f7e6-41ba-8610-3bf19c07174e'::uuid,'loadReader','70ad68d5-8554-4512-8c00-8076c15a70c6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('31720aa8-f7e6-41ba-8610-3bf19c07174e'::uuid,'loadBilling','9a15e499-d6e9-4ea1-8723-d31be4f6bb67'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('23006860-1b74-4123-88f5-4cc131dcd211'::uuid,'loadReader','ce9ec7c7-b202-4048-87c5-c0e867298d76'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('23006860-1b74-4123-88f5-4cc131dcd211'::uuid,'loadBilling','b8541675-ce9a-4e18-8342-7e32d217a4a4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('62d0e1e2-f8e1-486f-80fe-ed9d456d2e9d'::uuid,'loadReader','87a7f678-61d0-4079-8757-dd8dd86e19f7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('62d0e1e2-f8e1-486f-80fe-ed9d456d2e9d'::uuid,'loadBilling','b017973b-5dbc-4d63-8d05-7145ea361b11'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3a3cac6a-48c1-4a18-86ba-ae70d839476a'::uuid,'loadReader','aaf42785-7680-4403-8789-d323d4cf34c6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3a3cac6a-48c1-4a18-86ba-ae70d839476a'::uuid,'loadBilling','b7bcd63c-3cb1-4488-8dca-44dd23896680'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f11e8c27-2ecf-4bbe-8dbe-4e0b91c16366'::uuid,'loadReader','d22c1376-beac-419d-84e1-4932248e439b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f11e8c27-2ecf-4bbe-8dbe-4e0b91c16366'::uuid,'loadBilling','73fb23dc-3cd7-410d-8c10-f7f2603dd659'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4c9857e9-a820-44fc-86bb-4c98011bd4ff'::uuid,'loadReader','6069aeba-e50a-40e9-8c9b-4053f6e4294b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4c9857e9-a820-44fc-86bb-4c98011bd4ff'::uuid,'loadBilling','828cfc5d-fb9c-482e-8958-581b4b5b648a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f8595cd3-c1d8-4a94-8802-9be26e25a8ad'::uuid,'loadReader','7342111e-4db3-417b-8587-d57d26e3dcb3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f8595cd3-c1d8-4a94-8802-9be26e25a8ad'::uuid,'loadBilling','9b2c389a-5ff8-49e9-8dea-7c448dc969c4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('582a52de-720a-4e37-8e25-a6a721c044dc'::uuid,'loadReader','0003c719-917f-45d8-8b42-f309c32c870c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('582a52de-720a-4e37-8e25-a6a721c044dc'::uuid,'loadBilling','2e813f88-b75d-470c-83dc-02e5afd83b90'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('600a7fc0-93f8-47ae-88f9-d869cadb79a6'::uuid,'loadReader','6de1ba9f-419e-4eef-83a9-290cbf04b17d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('600a7fc0-93f8-47ae-88f9-d869cadb79a6'::uuid,'loadBilling','43d2787a-a804-4aa1-875c-eb814a0b8ed8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9860530d-724e-4437-8f7a-e8a071df760b'::uuid,'loadReader','0f1e5e72-060a-46ab-806b-525ee51468c2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9860530d-724e-4437-8f7a-e8a071df760b'::uuid,'loadBilling','9a2faea5-5797-469a-8cfc-8eb7873d0824'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e062529c-8cae-44c2-89d6-840eb959f75c'::uuid,'loadReader','9af6e4cf-5f7d-4557-8a8d-a8eb03acea71'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e062529c-8cae-44c2-89d6-840eb959f75c'::uuid,'loadBilling','ae0ada56-f816-4130-80ab-faef243fd9d1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c198f0ba-6c21-4ef6-83a3-4d2e53b72729'::uuid,'loadReader','1c898e04-b8da-4aaf-8666-1a0a54c6975f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c198f0ba-6c21-4ef6-83a3-4d2e53b72729'::uuid,'loadBilling','caf503bd-5413-458b-859a-1e2a12180190'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fb4bac71-2544-42c9-8fe9-9f67dd95b71a'::uuid,'loadReader','8503aeec-d509-4653-8dc4-7a0b39b62523'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fb4bac71-2544-42c9-8fe9-9f67dd95b71a'::uuid,'loadBilling','99741446-d80b-47c7-8cc5-f327f8cc689c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fad2770c-3506-46c6-849b-023aced551da'::uuid,'loadReader','11fb91d4-1d5c-4b5f-8606-a4e812890d7c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fad2770c-3506-46c6-849b-023aced551da'::uuid,'loadBilling','c0dbd9be-814e-48e9-8ead-096da5d1df9b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('10e5ca72-8ebf-4487-81a1-40011255c54d'::uuid,'loadReader','bc444b20-b39e-4fcf-8470-b521a89edbe0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('10e5ca72-8ebf-4487-81a1-40011255c54d'::uuid,'loadBilling','5eab6ae2-f9c9-405d-849e-87e803c930e3'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('777614e4-035a-476a-8af7-b7992442bbf7'::uuid,'loadReader','fa274b21-81c2-4d49-82b2-6658dd6c3cf9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('777614e4-035a-476a-8af7-b7992442bbf7'::uuid,'loadBilling','3a7a8172-e13c-434b-863f-10040a8ed1b0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('77e5eb12-3e03-4f82-8c77-6dcee5d2016c'::uuid,'loadReader','91a12d85-94cf-44a4-833f-ccec131c433b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('77e5eb12-3e03-4f82-8c77-6dcee5d2016c'::uuid,'loadBilling','5f850eef-9d5c-483b-83b4-3009b78e1d27'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4f69f21c-d126-4fcc-8fcb-ea9c8c9594e4'::uuid,'loadReader','1db1c5dd-b01c-4840-8471-e1cc1e57006f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4f69f21c-d126-4fcc-8fcb-ea9c8c9594e4'::uuid,'loadBilling','330923bf-a915-4ee2-8769-d83da460c06d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a3ff4f0d-4a62-4b39-8774-131d7441199f'::uuid,'loadReader','617a6bc6-5379-4514-869d-9d66df2b89f8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a3ff4f0d-4a62-4b39-8774-131d7441199f'::uuid,'loadBilling','b26e2bd8-3e3b-47c3-82c4-d88ed871b101'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4451113c-1840-428a-85d9-8e8496798960'::uuid,'loadReader','1df12706-9404-464b-88b0-9b972b737269'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4451113c-1840-428a-85d9-8e8496798960'::uuid,'loadBilling','e1d41fe4-5fd6-42a1-8aa8-8085c5244f48'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ba470464-1bbc-4f0d-81eb-539c611d58e4'::uuid,'loadReader','c3daa27d-cd5b-482b-83ef-2d280cfc9db7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ba470464-1bbc-4f0d-81eb-539c611d58e4'::uuid,'loadBilling','55822a7d-05ef-46e7-84c1-b5cfac2c7cb7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('22b6d469-0cb8-4e29-87f9-981e2f8e53ca'::uuid,'loadReader','df8536f9-c158-42f3-8f93-21d45d8b2983'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('22b6d469-0cb8-4e29-87f9-981e2f8e53ca'::uuid,'loadBilling','9696de4c-852f-4677-88dd-d6a4d483578a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0976ed9e-eca7-4141-8672-d1cb30850d80'::uuid,'loadReader','9bbb0b94-546e-4e24-84bd-6eff16b14e72'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0976ed9e-eca7-4141-8672-d1cb30850d80'::uuid,'loadBilling','c62f84d2-d446-40e9-80fb-37225ee04bd8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2cbbf3ef-3e57-4721-8721-0bc59ee700b2'::uuid,'loadReader','cb3a9dd2-3c18-4cec-8567-2fcf97e28617'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2cbbf3ef-3e57-4721-8721-0bc59ee700b2'::uuid,'loadBilling','61c21d27-8769-4183-8456-2f5726b92c75'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('826fb914-1ee1-4a8c-8874-7bd287b8f820'::uuid,'loadReader','ec6ba79b-742b-44d2-859b-86faa44c31e9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('826fb914-1ee1-4a8c-8874-7bd287b8f820'::uuid,'loadBilling','ebaeff01-1ded-4fed-805d-fdbc9b139e2a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d312f0e4-4b9a-4f2e-83e9-9cba66716983'::uuid,'loadReader','67e6c29d-d2ac-40e3-8983-cd999548d138'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d312f0e4-4b9a-4f2e-83e9-9cba66716983'::uuid,'loadBilling','21890390-eb88-42ed-84b0-77e540690828'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7a933f4a-8d34-42bd-80a1-7b9722263910'::uuid,'loadReader','02d4648d-ac0a-4298-8074-229fd752fab4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7a933f4a-8d34-42bd-80a1-7b9722263910'::uuid,'loadBilling','703112ef-bcae-4ce8-8799-12bce11fad46'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('91ee6c78-0af4-414f-8856-7b855297b211'::uuid,'loadReader','a8a9a110-c399-48dc-844e-c4b5bde0cc8b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('91ee6c78-0af4-414f-8856-7b855297b211'::uuid,'loadBilling','3c7d27a7-0283-43cd-8725-e547f951a816'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('380ae35a-410e-4232-8e74-450970526431'::uuid,'loadReader','25131b2c-ed4d-472a-8079-efa475048abc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('380ae35a-410e-4232-8e74-450970526431'::uuid,'loadBilling','f9abe4d7-be56-4ed2-849f-679d56d0da47'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('81c3e7d6-fa23-4b39-8fb5-4e301efea967'::uuid,'loadReader','4b895870-d3dd-4109-8132-a7aa05ffc953'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('81c3e7d6-fa23-4b39-8fb5-4e301efea967'::uuid,'loadBilling','65d1f1e4-aee0-4e37-883b-2957ecac5225'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fccf8300-f191-49fd-8939-a68872c92064'::uuid,'loadReader','55a9709c-f7a6-470e-85f5-827f0d9051a9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fccf8300-f191-49fd-8939-a68872c92064'::uuid,'loadBilling','bdb30c52-54b8-491f-8521-da13b4806a92'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('04e40de1-4142-4291-8382-58231e59d074'::uuid,'loadReader','5020e48b-0bef-4fa6-8bd2-beb87e639f5c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('04e40de1-4142-4291-8382-58231e59d074'::uuid,'loadBilling','7c8e4483-3de0-4d3b-8050-312416798810'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('91ef5d38-35f5-4971-8e7e-0a6639c79ab9'::uuid,'loadReader','492a5f0a-1d16-43d7-8987-00513499210d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('91ef5d38-35f5-4971-8e7e-0a6639c79ab9'::uuid,'loadBilling','6cf2eb4c-674b-4710-87ee-f18f81dccf3f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('eddac976-2162-4576-883c-a26f66b14011'::uuid,'loadReader','6bbc97b4-6af6-4ff1-8f67-36eb75330635'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('eddac976-2162-4576-883c-a26f66b14011'::uuid,'loadBilling','22aadafc-51ab-4ca5-87fb-b34f0507324c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9f7e25a2-7355-49c7-851c-550c58d62871'::uuid,'loadReader','4ce78335-81d6-4d22-8179-2b9ca5c4212f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9f7e25a2-7355-49c7-851c-550c58d62871'::uuid,'loadBilling','659fd19c-4174-4467-8189-8849e276a05b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5e59f791-f5b3-43ca-833d-b636a899779d'::uuid,'loadReader','6153c753-b07f-4ed7-84d5-1a202bfb59ff'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5e59f791-f5b3-43ca-833d-b636a899779d'::uuid,'loadBilling','1f5de05d-84f1-4065-8877-6adb2b04beb5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1f39dd56-ec3c-45db-85a2-550963604163'::uuid,'loadReader','6631bec0-b8b4-4f2f-82ef-31b9adaa05ef'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1f39dd56-ec3c-45db-85a2-550963604163'::uuid,'loadBilling','1050873e-a016-4237-8846-0e7607f15daf'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ff0fe3a7-cb81-4c46-8209-94e584f24e52'::uuid,'loadReader','58a8c52b-0ffb-4197-86d7-01e665c1d580'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ff0fe3a7-cb81-4c46-8209-94e584f24e52'::uuid,'loadBilling','c1540db7-f56f-40e0-8b91-243535ca9076'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('eb06333e-2665-48aa-86bc-184b5f560fdd'::uuid,'loadReader','9b8b5981-fff9-4442-85a0-ffd58d83d05f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('eb06333e-2665-48aa-86bc-184b5f560fdd'::uuid,'loadBilling','3b400bec-5308-4f19-81ac-fc14a14b66e4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0b044972-ba52-498b-8656-7425b5301a8f'::uuid,'loadReader','250cfebf-9cf6-4a3a-86ad-7ec6e5e2cc64'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0b044972-ba52-498b-8656-7425b5301a8f'::uuid,'loadBilling','098ad323-2f85-43ae-8ab3-0f929a2e4b16'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c9c05286-7034-481d-8402-fe6d339d20c9'::uuid,'loadReader','cbbc2d07-9c46-4ac7-83a5-bc1a454bdbc5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c9c05286-7034-481d-8402-fe6d339d20c9'::uuid,'loadBilling','d5271afe-3c8f-4a57-83c3-b4a9b9e4c9c5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('13f8f64f-42e8-4b3f-88ae-93f3acc07fe2'::uuid,'loadReader','e6ecdcb9-b3bc-45ac-851b-2bef2fbf4eb9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('13f8f64f-42e8-4b3f-88ae-93f3acc07fe2'::uuid,'loadBilling','4ab84d57-7907-4d82-8778-261f3c0e83d4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d0f3c15c-f3f5-4de3-8ca2-4539dfe9dd99'::uuid,'loadReader','44e13252-8b58-4370-82e0-d10670e70929'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d0f3c15c-f3f5-4de3-8ca2-4539dfe9dd99'::uuid,'loadBilling','5398b4ee-885b-4228-8170-8fa98d3c2896'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0944de64-568b-46a2-88dc-7038872fd572'::uuid,'loadReader','ab1a1385-2173-49ac-8e8f-255d8243ddc3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0944de64-568b-46a2-88dc-7038872fd572'::uuid,'loadBilling','13139034-17d1-40d4-88d5-9faa503f316f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b11c5036-914a-4cfb-8cb3-ab2590fc0c42'::uuid,'loadReader','4cd90959-1a4f-48c9-8ee0-0cc8b4ded558'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b11c5036-914a-4cfb-8cb3-ab2590fc0c42'::uuid,'loadBilling','b36d5925-e908-4de3-8b49-4838516566cb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c330e32d-cc2a-4c01-8436-a9d2f88ddd73'::uuid,'loadReader','e5d810f0-b3e4-4bb0-82ba-1d705ce7c211'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c330e32d-cc2a-4c01-8436-a9d2f88ddd73'::uuid,'loadBilling','eef2f845-d2ad-4534-82f8-33020414cd34'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('708fd0e1-e5c0-4bd7-82d2-1b29cc801403'::uuid,'loadReader','9c785a56-3550-41d7-8c04-69601b14f9c3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('708fd0e1-e5c0-4bd7-82d2-1b29cc801403'::uuid,'loadBilling','2d848a13-831f-47a3-899f-440b61b72894'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('243b116f-310d-4bef-8de5-96b961215dcf'::uuid,'loadReader','cef6eccc-d16c-4dca-877f-9fe8ad1b2c20'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('243b116f-310d-4bef-8de5-96b961215dcf'::uuid,'loadBilling','bf535c25-f488-4771-83a6-4e816fc27286'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b5dc8da0-8f14-42f7-8f33-c2b937eaf9ba'::uuid,'loadReader','193cc47b-fcd7-4acf-844c-18349be4f96a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b5dc8da0-8f14-42f7-8f33-c2b937eaf9ba'::uuid,'loadBilling','dfcdde23-0fb7-4e73-812b-e8997b94c3c8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1031845d-82f3-4d18-83a6-107a14698692'::uuid,'loadReader','8a92a39f-5c76-4393-8bd1-f350d88889e3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1031845d-82f3-4d18-83a6-107a14698692'::uuid,'loadBilling','4ca6e0ed-9680-4a8b-895c-07a630b190fa'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0f39a6aa-53ad-4f71-858b-8586cf65be38'::uuid,'loadReader','07f2728f-32d6-4378-8b21-5208066a9703'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0f39a6aa-53ad-4f71-858b-8586cf65be38'::uuid,'loadBilling','9bac4351-7f03-4436-8376-30df6fc3d668'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('87d64230-c14e-42a9-8696-e527a1d967e8'::uuid,'loadReader','b60ab7c9-353a-4432-831b-3ffa9ae96221'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('87d64230-c14e-42a9-8696-e527a1d967e8'::uuid,'loadBilling','22a99c0c-67e3-4d41-8351-ad451ebdc95b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3b5060a6-2d14-4fab-83a0-ca9e9acd362c'::uuid,'loadReader','944b1f26-560e-4b67-804a-562d98228cfd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3b5060a6-2d14-4fab-83a0-ca9e9acd362c'::uuid,'loadBilling','728857ac-adec-4e0c-8f3a-efadb3203375'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('61ddaffe-9a58-4190-8c56-b5ee939de519'::uuid,'loadReader','15ed550c-9d5f-415d-8769-f2cc270d8aa4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('61ddaffe-9a58-4190-8c56-b5ee939de519'::uuid,'loadBilling','40791033-4aaa-4027-8e17-27a2c39c09e6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c5918fce-dace-4b51-82d8-09689e1a201f'::uuid,'loadReader','f9aa3933-d1b6-4c75-87c5-60fff12d6819'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c5918fce-dace-4b51-82d8-09689e1a201f'::uuid,'loadBilling','23032d4e-5fbb-4c02-80ef-4b633ff16904'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9d5e62bf-6144-4e77-84bd-fb7807de0670'::uuid,'loadReader','2d4f7035-1060-470e-89dc-fec1aa76ab4c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9d5e62bf-6144-4e77-84bd-fb7807de0670'::uuid,'loadBilling','83a05d1b-b96c-41ef-8dc1-c3242d96e159'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('875cbbdb-d6d3-46ab-8300-e09a97f7e833'::uuid,'loadReader','8fc73297-c346-4924-81b6-f5f1ea94ba9a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('875cbbdb-d6d3-46ab-8300-e09a97f7e833'::uuid,'loadBilling','10bb6c4d-18e9-4394-8074-1d8066dcaef5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('90df5765-96c2-48df-85f8-dfd05517d516'::uuid,'loadReader','e3d8b4c3-bccd-42d0-85a0-eeadbd765176'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('90df5765-96c2-48df-85f8-dfd05517d516'::uuid,'loadBilling','3f5e6f74-58ed-4457-8ec0-28fb0368c99f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('095b8470-41b3-4c1a-874a-6ea3ea003926'::uuid,'loadReader','d344a889-3870-45ac-8334-8ab747724752'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('095b8470-41b3-4c1a-874a-6ea3ea003926'::uuid,'loadBilling','714527bd-eb62-47f0-8984-979bc1feac68'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('751c8246-fa6d-40bd-814b-57892415c294'::uuid,'loadReader','e7095248-15fe-4e65-8e6e-d0ef784d8e4f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('751c8246-fa6d-40bd-814b-57892415c294'::uuid,'loadBilling','a35f6bed-2856-405d-8b0c-32765d9a81bb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cb4a8652-29b1-46cb-80fd-a06881459826'::uuid,'loadReader','c300c7dc-21d9-4d59-8943-7ad4553487dc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cb4a8652-29b1-46cb-80fd-a06881459826'::uuid,'loadBilling','6694cdda-a7c6-4bdd-868a-9b970204a63c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b14eaeee-1377-48ea-8747-34327b61e755'::uuid,'loadReader','76e1c37c-0cf8-4668-8d8b-4df73416ee6e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b14eaeee-1377-48ea-8747-34327b61e755'::uuid,'loadBilling','e3f996fa-84e2-4454-8219-918cc5986ad7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7fc526da-33d9-451f-8bbd-7504710d30f8'::uuid,'loadReader','4c430b67-5900-4729-882b-0d6531600260'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7fc526da-33d9-451f-8bbd-7504710d30f8'::uuid,'loadBilling','4d20e318-3b6f-4dcf-8522-c03def4b275c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a312ad93-580f-4057-8ca9-6a8e4a61a8b3'::uuid,'loadReader','a31112da-5662-42b2-8909-217fdd43d119'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a312ad93-580f-4057-8ca9-6a8e4a61a8b3'::uuid,'loadBilling','7fda5d4e-55ed-414c-8ae9-58b9e24c0d5d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7d1f2a88-4c49-4b5e-8c0c-d2f007eb639f'::uuid,'loadReader','b6954e32-67a4-4588-8548-e07c80d5e7b7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7d1f2a88-4c49-4b5e-8c0c-d2f007eb639f'::uuid,'loadBilling','c6970d03-84a9-43a9-8ca1-9e02aacafb72'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5573f0e5-d69d-4316-8b80-debd9e5f6dd2'::uuid,'loadReader','9dd2be75-1da6-4122-8d97-49769853fe15'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5573f0e5-d69d-4316-8b80-debd9e5f6dd2'::uuid,'loadBilling','402c1b0e-63a1-4089-8691-365dfa1f9110'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('869f42ee-7af1-446e-8627-6345604d8440'::uuid,'loadReader','af2e1c58-ce6b-48cd-8e9a-f2e7c801fe4e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('869f42ee-7af1-446e-8627-6345604d8440'::uuid,'loadBilling','654f57b5-c262-4f08-8736-afc9b96d9030'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ab0d2faa-7e15-401b-850e-f71004345841'::uuid,'loadReader','8a0ff064-9d38-491d-8a68-e12ce6a35dcb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ab0d2faa-7e15-401b-850e-f71004345841'::uuid,'loadBilling','95dbcac1-e0d3-4736-8f21-2e9181052abb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('965e42bc-1c5b-42ab-8f48-4f33c956ddce'::uuid,'loadReader','5a445476-a625-4d08-8b8b-bdde3e1c3d34'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('965e42bc-1c5b-42ab-8f48-4f33c956ddce'::uuid,'loadBilling','acece90a-960b-4ee9-8c65-802a792cfc49'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e92e9a60-a192-40b2-8426-db6e54fb635a'::uuid,'loadReader','7ecab14b-78af-49f0-89ca-d5971511c9e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e92e9a60-a192-40b2-8426-db6e54fb635a'::uuid,'loadBilling','cce5ed7d-1091-4027-8895-88b70a684147'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6b3f339b-8098-41b7-8cf7-5a847f7eda79'::uuid,'loadReader','8268ea15-22f3-4c14-8a75-6489411fe10f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6b3f339b-8098-41b7-8cf7-5a847f7eda79'::uuid,'loadBilling','eef21459-57f5-4c88-8730-41e2c36ecfdb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b91bc9d5-e7b3-4b44-842e-35c2a25e16b7'::uuid,'loadReader','4be76fce-5f99-4394-8fe9-24881c241882'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b91bc9d5-e7b3-4b44-842e-35c2a25e16b7'::uuid,'loadBilling','c0f285e1-12c2-4c8f-8f2a-6c53b0ff6051'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('574f28b6-7b06-4cd7-8131-6eedfc3b0f71'::uuid,'loadReader','5bba38f5-a97a-4ad0-8a69-28145d5176fd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('574f28b6-7b06-4cd7-8131-6eedfc3b0f71'::uuid,'loadBilling','7c6d4659-6966-4721-844e-a164f6d4db7e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f658ca81-0672-4395-8f18-e4d624708efb'::uuid,'loadReader','8f80c394-15c9-4b3f-8475-717f728ba8b2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f658ca81-0672-4395-8f18-e4d624708efb'::uuid,'loadBilling','4d4947a3-4ef4-46f9-8491-ae2c822d206d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c599a5ea-68b2-49e6-8b60-9f7f5cc86b90'::uuid,'loadReader','1981994c-42d9-480d-8058-0c5110b520d2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c599a5ea-68b2-49e6-8b60-9f7f5cc86b90'::uuid,'loadBilling','e416ff1e-4ae4-49ab-886e-9b0166ce6522'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('03463cf6-b1a6-4767-8fe2-ab7616389b49'::uuid,'loadReader','b1820c53-777b-4e7c-85ac-cc853d219b85'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('03463cf6-b1a6-4767-8fe2-ab7616389b49'::uuid,'loadBilling','7c6034b5-915d-4ad5-87e8-50870aa7091e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f1d9a6d1-c247-4e1f-8198-4d0513e00e1a'::uuid,'loadReader','dbdf7a48-ad6a-493a-857b-3299436976d7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f1d9a6d1-c247-4e1f-8198-4d0513e00e1a'::uuid,'loadBilling','c46f008f-ed6b-464e-88ad-211a9a209bc6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fcad99d9-e9eb-45af-802a-4a190810e1d6'::uuid,'loadReader','24c8adf1-3daa-4a9c-8a56-5b28d8b8fb37'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fcad99d9-e9eb-45af-802a-4a190810e1d6'::uuid,'loadBilling','176039dc-7df8-472f-87af-727a9a7c835e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('aa911f69-c9a5-4bd8-8079-ffa07838e172'::uuid,'loadReader','646e76f0-4f47-42e7-8b7e-7c537d00001a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('aa911f69-c9a5-4bd8-8079-ffa07838e172'::uuid,'loadBilling','fda90af8-308d-4804-8c08-b527c9375680'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b011abcd-df39-4cb1-86d5-daca86864d0c'::uuid,'loadReader','9d9071c3-28b8-474b-8b66-2ce3fc60b57d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b011abcd-df39-4cb1-86d5-daca86864d0c'::uuid,'loadBilling','7f5748e7-3fcf-404f-8602-0d1a9520d751'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3ab3ac90-29f9-40dc-8a58-e6c2b219eb0c'::uuid,'loadReader','54fee994-4b7b-460f-85b0-bd26d33e8f41'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3ab3ac90-29f9-40dc-8a58-e6c2b219eb0c'::uuid,'loadBilling','0f5e3ee7-df0d-4440-8894-75147019c622'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e1f32113-02a6-46be-8feb-d61078ce43df'::uuid,'loadReader','cae07df3-be6d-4f06-83b4-d5954c55c779'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e1f32113-02a6-46be-8feb-d61078ce43df'::uuid,'loadBilling','89a7fb17-23b9-4550-84ff-69b10caa08e0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b57cc7d9-f9f0-47fc-8895-9a636d762ec8'::uuid,'loadReader','63c6b926-a7c0-4cdf-8d97-e49c45774e92'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b57cc7d9-f9f0-47fc-8895-9a636d762ec8'::uuid,'loadBilling','7ac86906-6707-48f2-878e-d858b1e73e7d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4a5238e5-1e54-4e2c-88f6-b8a8672cb597'::uuid,'loadReader','a7942379-a7b7-4fb9-8048-703081da2dca'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4a5238e5-1e54-4e2c-88f6-b8a8672cb597'::uuid,'loadBilling','d1ff072e-ae58-4001-8931-a5d86fe80bb0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('20406411-3299-408d-8651-b820e3523d91'::uuid,'loadReader','0bacb65a-de42-4e0a-87b5-35b25e561c53'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('20406411-3299-408d-8651-b820e3523d91'::uuid,'loadBilling','266e43fe-6f67-4aa1-8f1f-385bd3e4a991'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1f8114b2-8f37-4455-881a-5b60a4334460'::uuid,'loadReader','b37cf46b-37c5-49f9-8d6b-e72fa99c2934'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1f8114b2-8f37-4455-881a-5b60a4334460'::uuid,'loadBilling','5db8c85d-4650-461e-8e85-bd2074bb0171'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f267b242-47f8-4cbf-85e7-1611c21e0796'::uuid,'loadReader','d542e68c-c9d1-4c73-8b70-dcb71ac4a371'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f267b242-47f8-4cbf-85e7-1611c21e0796'::uuid,'loadBilling','54d9b9a5-c8b1-439f-8591-e918f9057dfe'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('57c682b4-9e43-4376-8db8-1441c4e80494'::uuid,'loadReader','07c261a6-217e-46b6-8370-21065cb67241'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('57c682b4-9e43-4376-8db8-1441c4e80494'::uuid,'loadBilling','36570058-e65f-4161-82bd-75e7cb2382b5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('520ec1d1-ac60-489d-864f-154c74809505'::uuid,'loadReader','02fee408-a05a-4386-8626-1e3eeb81954b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('520ec1d1-ac60-489d-864f-154c74809505'::uuid,'loadBilling','3717e381-80f8-48e9-8f2f-49447781755b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f79e7dce-d984-47ce-89b3-a8f46900f0b7'::uuid,'loadReader','b45e442c-004d-4e59-843a-7d71a041ff67'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f79e7dce-d984-47ce-89b3-a8f46900f0b7'::uuid,'loadBilling','55937329-f41d-4901-87f7-e83f54ad1905'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bbcacf39-4e82-47c5-8944-4ae0d0120dfb'::uuid,'loadReader','049c227e-985a-4c14-8de2-06c448633ddf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bbcacf39-4e82-47c5-8944-4ae0d0120dfb'::uuid,'loadBilling','c18ab0cd-8f18-4120-8a62-518a72893797'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('dc30bb28-7dcd-4139-867d-84dc9e60d5e7'::uuid,'loadReader','66ff470c-bc9b-4fe8-80b6-82b1c7d95b3a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('dc30bb28-7dcd-4139-867d-84dc9e60d5e7'::uuid,'loadBilling','756d3c8d-363d-4274-8446-a1cfdd961433'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e7516883-c919-4177-832a-e104ff13d67d'::uuid,'loadReader','9ea9a712-45da-404d-8aee-68d2e4e78fe1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e7516883-c919-4177-832a-e104ff13d67d'::uuid,'loadBilling','5f62bb07-185f-4c36-88a2-0829fc9ef09a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('56ae5a66-783a-43a1-8f8b-7ef7e7aac6a8'::uuid,'loadReader','2be0c7fd-c61b-4945-8335-cb39ce8e08fc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('56ae5a66-783a-43a1-8f8b-7ef7e7aac6a8'::uuid,'loadBilling','09c6a148-ad31-4cec-8359-5064b0a140a7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2ec43565-724c-4c36-8754-3b36513d0f25'::uuid,'loadReader','346a14a9-a7a7-4f3d-8819-ad75355e86de'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2ec43565-724c-4c36-8754-3b36513d0f25'::uuid,'loadBilling','f67b190e-8732-45a2-8185-2c590d0e13f1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8dce5ae1-b8c6-4737-8091-9fbc2e788e87'::uuid,'loadReader','d8ae06f3-86cf-4cb5-8f6e-fc9113e963a5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8dce5ae1-b8c6-4737-8091-9fbc2e788e87'::uuid,'loadBilling','da60600f-e8c7-444b-879c-cd6b77e6a56a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cc59f899-3b91-4fee-8b2c-b9dcdfaa2b7e'::uuid,'loadReader','ef3036ae-1e67-483e-82c8-fe389a3f9e77'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cc59f899-3b91-4fee-8b2c-b9dcdfaa2b7e'::uuid,'loadBilling','8d976a35-34c0-4d2e-890b-1e517ba22c11'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4130a1d7-4ac4-49b4-85e8-23384deeeaf2'::uuid,'loadReader','319800bf-e331-495a-85fc-2af0c013f666'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4130a1d7-4ac4-49b4-85e8-23384deeeaf2'::uuid,'loadBilling','58a633e0-9458-4380-8540-a99e51f1985a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d63a542a-9106-4c4a-8874-9f2b4070d34a'::uuid,'loadReader','0d1055d4-4155-41d0-8e12-3058c17a74cd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d63a542a-9106-4c4a-8874-9f2b4070d34a'::uuid,'loadBilling','dee98e67-9b78-4f98-88e0-d736510ac7a5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1cbb8e4a-b351-448e-8d7f-df9595607e3a'::uuid,'loadReader','11530285-451c-49ea-8628-ae07512ae2b9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1cbb8e4a-b351-448e-8d7f-df9595607e3a'::uuid,'loadBilling','61377aeb-fd34-4ca7-81ba-239fbaae8f59'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('979e03c6-e26f-4f4c-85ee-e84fa962e41a'::uuid,'loadReader','16eabf35-8915-4cbf-8015-1b18110f3db3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('979e03c6-e26f-4f4c-85ee-e84fa962e41a'::uuid,'loadBilling','ebec8416-2e1e-42ea-8e2f-255d44189b51'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('52bea53c-c251-4f85-89cd-9f451fbbe5f7'::uuid,'loadReader','a63195c1-554d-4c50-828d-716bc4b1b81d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('52bea53c-c251-4f85-89cd-9f451fbbe5f7'::uuid,'loadBilling','edddd686-ca1f-45ef-8a88-99dce13d9b1d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('97249d9c-0ae3-48e0-8068-61755c80e741'::uuid,'loadReader','41bcbea0-7bc7-4e95-82df-1c88a437e490'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('97249d9c-0ae3-48e0-8068-61755c80e741'::uuid,'loadBilling','9e03fde3-3eac-40e1-85c9-69e5bb428a50'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('334c9e65-cb3c-4b69-8ef8-f57f14e01275'::uuid,'loadReader','cca76bdd-01f6-4286-8bdf-9873878298de'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('334c9e65-cb3c-4b69-8ef8-f57f14e01275'::uuid,'loadBilling','5664bd22-e932-4280-8627-00b9a401cf96'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('be812378-9e6a-476c-81bc-11e4249bce75'::uuid,'loadReader','d3dec821-f7e7-46e5-8f40-c293e380daf4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('be812378-9e6a-476c-81bc-11e4249bce75'::uuid,'loadBilling','a5af2d47-4ae6-4f21-8c44-d048f2a2b110'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e0cc3675-1ecb-4039-81c6-8e9c42c87d84'::uuid,'loadReader','975698cf-99e3-4a75-8003-73cf92e97481'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e0cc3675-1ecb-4039-81c6-8e9c42c87d84'::uuid,'loadBilling','30130b94-1463-4002-863b-678660b3e70f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b079257b-aa48-4b76-8f85-ae4d14d3aebc'::uuid,'loadReader','742e9443-8b32-4938-8e19-e3bc3164665e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b079257b-aa48-4b76-8f85-ae4d14d3aebc'::uuid,'loadBilling','3c0b138f-583d-44a8-80d5-891b1d303083'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('edbf63c2-3429-491b-8b3f-a1d293a59184'::uuid,'loadReader','66d5cbaa-2983-434e-8606-9bde5b3b5e35'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('edbf63c2-3429-491b-8b3f-a1d293a59184'::uuid,'loadBilling','21776884-0c2e-4056-8275-fe2610d999bd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('07db23a0-c5c1-4d94-8479-1a2dbfb1efcf'::uuid,'loadReader','34ec8e54-1f69-4de2-8169-8f1037c23e10'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('07db23a0-c5c1-4d94-8479-1a2dbfb1efcf'::uuid,'loadBilling','89b8ab02-7831-4783-87f1-4c5d04ce4a7c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9ba4f543-e553-4e84-869a-751e73ae955c'::uuid,'loadReader','56d2bb46-184b-4006-8d5b-f00b96703592'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9ba4f543-e553-4e84-869a-751e73ae955c'::uuid,'loadBilling','ed1c812f-3b0b-4302-8f0b-43755a6606d5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('38d20e62-4ba5-49d7-8ae2-9371d0274302'::uuid,'loadReader','d056b7d5-bed9-43b9-815e-e38784749f39'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('38d20e62-4ba5-49d7-8ae2-9371d0274302'::uuid,'loadBilling','5762d77b-7f1b-4a22-8c75-cd5dc73c63c6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('df67c8c0-2a4a-4779-8825-8a8dbed4b2c1'::uuid,'loadReader','26defbfd-b2fb-45a2-8168-ce580afc6015'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('df67c8c0-2a4a-4779-8825-8a8dbed4b2c1'::uuid,'loadBilling','716ac556-67cf-47b0-81f8-92671f9f6640'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('88a9ed4d-7f53-4a51-84dc-d33f0085f840'::uuid,'loadReader','3d749395-666a-450f-8f8c-3ed22ee59725'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('88a9ed4d-7f53-4a51-84dc-d33f0085f840'::uuid,'loadBilling','d7756ce3-e0f2-4ef7-8843-6350d403d6d5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('138ee2fb-4cde-4a2b-8fc9-babe378aa32c'::uuid,'loadReader','012f64e0-f484-4e9f-8cd4-fc1fa0f9ac34'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('138ee2fb-4cde-4a2b-8fc9-babe378aa32c'::uuid,'loadBilling','89d45a9d-2471-4c00-825c-43a0948afec9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('eb68b170-17d0-47e4-81c8-60534ad708ab'::uuid,'loadReader','7ca8b340-a486-443c-8753-a46290c4ad05'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('eb68b170-17d0-47e4-81c8-60534ad708ab'::uuid,'loadBilling','e5b32555-0bce-4c09-80f9-a2e785c9cf11'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cbc3b6e1-83f3-40dd-8d94-d1450fa9780b'::uuid,'loadReader','9962dff4-fa16-4e21-8512-00ca77edb07d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cbc3b6e1-83f3-40dd-8d94-d1450fa9780b'::uuid,'loadBilling','84f2d453-d5bb-4d76-89a7-ee22d8eb89c5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8b4028e5-0efd-4ba5-8da3-44a6722f27f2'::uuid,'loadReader','15a60284-4e9c-437a-88f0-b73085918dd7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8b4028e5-0efd-4ba5-8da3-44a6722f27f2'::uuid,'loadBilling','90f5d783-2ebf-468b-85b2-777f50cc4a27'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b0fe7a58-527e-482a-8212-d5875a0c80aa'::uuid,'loadReader','8f7a255b-7b64-46e9-8ca2-91b7d98a6eee'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b0fe7a58-527e-482a-8212-d5875a0c80aa'::uuid,'loadBilling','379ae254-f0b2-4ea2-861e-a0b646e1b874'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fb9ce446-ec52-4304-8180-1bf0d0a7e5f3'::uuid,'loadReader','f1f4696f-cc4d-4783-87d5-30d410291e1f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fb9ce446-ec52-4304-8180-1bf0d0a7e5f3'::uuid,'loadBilling','c71e5913-71a9-48c9-8766-49f6871dace8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b2bd4543-31de-4137-845a-9bfccd4a1593'::uuid,'loadReader','3f1406ac-6b4c-4d7c-813d-a3ce8e2bdeed'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b2bd4543-31de-4137-845a-9bfccd4a1593'::uuid,'loadBilling','aa449f5a-285e-420a-82f4-d385a1b6ae2a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('66a00f12-16dc-4106-8b52-512f38244a95'::uuid,'loadReader','62bed2a3-d0a9-4987-8a67-58590024da9e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('66a00f12-16dc-4106-8b52-512f38244a95'::uuid,'loadBilling','5abd59bd-983e-4cc3-8fee-e64919adaa75'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f7b376da-cf4e-481b-8a39-766c48c3c921'::uuid,'loadReader','4a2194dd-06a6-4566-87c1-ed78f2dbf63c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f7b376da-cf4e-481b-8a39-766c48c3c921'::uuid,'loadBilling','a0bb8cb7-e008-4f23-81bd-f6f7cff60c11'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7dae3ee9-7418-4b3e-84bd-0d048166a870'::uuid,'loadReader','bc889720-4671-4cb4-8964-f11b92522474'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7dae3ee9-7418-4b3e-84bd-0d048166a870'::uuid,'loadBilling','faba36cf-4ff5-4e0a-8ccc-da274a262295'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f9048f32-2e36-43d1-8ac3-3ddfb672a829'::uuid,'loadReader','f05e2901-ce6a-4e0a-8f52-26ac8ef58b8b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f9048f32-2e36-43d1-8ac3-3ddfb672a829'::uuid,'loadBilling','b2a9e30d-a2ee-4a45-8caa-bc265ae2d15a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d490a20b-27ee-4da7-886a-9af5f5cc2a14'::uuid,'loadReader','fed475c3-090d-441c-8d70-7efefb7ae805'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d490a20b-27ee-4da7-886a-9af5f5cc2a14'::uuid,'loadBilling','2023292a-298b-4af9-8d93-c6e8d7450626'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('53dc0ed5-0c6b-4fab-88aa-9d834a242ad8'::uuid,'loadReader','3a044940-aac6-423a-8438-6f51accc0a9e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('53dc0ed5-0c6b-4fab-88aa-9d834a242ad8'::uuid,'loadBilling','b4c6f83c-7436-41f6-8dda-4710bf048ad9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e62c8a90-c9ad-4cae-87dd-a4f90cc1f7d1'::uuid,'loadReader','f3763f2b-5a5b-48de-8b1b-92b4cf9f61fc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e62c8a90-c9ad-4cae-87dd-a4f90cc1f7d1'::uuid,'loadBilling','2e1f0c1e-1ec6-49fa-812a-180deeb2c08f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('08498aa4-985c-431e-8714-3d9d48683f93'::uuid,'loadReader','e5276618-a74e-46ec-8d33-35522c9a81db'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('08498aa4-985c-431e-8714-3d9d48683f93'::uuid,'loadBilling','b18a6363-dc14-4b1e-8769-5d08954a5add'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8236691e-8917-40a7-884f-7183a7f9ee9a'::uuid,'loadReader','06cd8238-4f00-4c7d-8c9b-23226db44ddf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8236691e-8917-40a7-884f-7183a7f9ee9a'::uuid,'loadBilling','50fe7311-57f1-4db2-8b0f-023b5beec149'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('62d5c6ca-573b-484e-8798-b464a5512c76'::uuid,'loadReader','26c15603-d7e2-4169-860e-65741db59b27'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('62d5c6ca-573b-484e-8798-b464a5512c76'::uuid,'loadBilling','706b04c0-7a0a-48d4-856f-4dc9997e0b87'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('df374532-1fe2-4d13-8321-b7a237579b70'::uuid,'loadReader','534130ca-4de4-4877-8085-793dede633e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('df374532-1fe2-4d13-8321-b7a237579b70'::uuid,'loadBilling','8954bd90-f921-40fd-8425-1c74de2c2d69'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6b6ab6f8-574d-4eda-8f47-749d0eb05ccf'::uuid,'loadReader','febfbfd5-9e14-4243-8d26-a5fb6eb12191'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6b6ab6f8-574d-4eda-8f47-749d0eb05ccf'::uuid,'loadBilling','7f89d4fc-a856-4cf5-8cfd-f09417cf4b2f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5b455e63-3afb-41d5-88a7-ca7208ffcd87'::uuid,'loadReader','d1019bef-eeef-4a5a-83d5-b32f5b41e327'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5b455e63-3afb-41d5-88a7-ca7208ffcd87'::uuid,'loadBilling','af504020-f198-4df3-84cc-b38d3dbdae0f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b6a46f1f-a147-471d-8060-8e3348ac24da'::uuid,'loadReader','3fe03e91-4133-4e62-89ce-048ae9ef7dda'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b6a46f1f-a147-471d-8060-8e3348ac24da'::uuid,'loadBilling','61dc17fb-a2d8-45f1-852f-164af5813169'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b0a8f019-8e5f-411e-8808-bcf68e04139e'::uuid,'loadReader','d8965698-958e-4894-88dd-a3539c7fb679'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b0a8f019-8e5f-411e-8808-bcf68e04139e'::uuid,'loadBilling','58697f0a-7186-4df2-85a6-6b52550a4049'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9baa4e7f-3255-4b6e-8fff-3623ca71e919'::uuid,'loadReader','0ccb23bb-7b22-4415-8efc-8d1bf6947fa5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9baa4e7f-3255-4b6e-8fff-3623ca71e919'::uuid,'loadBilling','19c5c3e9-9615-4843-81ce-451069aacfee'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('523fa64d-33f7-4642-8d0f-93f8b26a4be7'::uuid,'loadReader','b705d273-2e92-4149-8371-4a91ac91875c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('523fa64d-33f7-4642-8d0f-93f8b26a4be7'::uuid,'loadBilling','8cbee4ba-63f8-4251-841b-bea24212398c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4b2dc450-503e-4a77-8294-d1d6dd57e528'::uuid,'loadReader','63803a18-2861-4461-8aee-41b71422ff79'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b2dc450-503e-4a77-8294-d1d6dd57e528'::uuid,'loadBilling','668c47aa-4319-4257-8e16-fb0dc959b026'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f77e9f9d-5b96-4ca7-8e31-311bb6b46b53'::uuid,'loadReader','ebb11198-eff8-44f4-8651-de60240b348f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f77e9f9d-5b96-4ca7-8e31-311bb6b46b53'::uuid,'loadBilling','584586c0-96a2-487d-87b9-99b0d94db9cd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8e65fdd2-2dac-493e-833c-6d2d36abf026'::uuid,'loadReader','5d76dd66-e16b-4cfe-88f8-7b559c56adb2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8e65fdd2-2dac-493e-833c-6d2d36abf026'::uuid,'loadBilling','3385bb36-e125-4c6a-8e35-9cde69e930fc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('262348fb-8dec-4b38-8c21-cb86a6ed7137'::uuid,'loadReader','f1eb564c-fb75-407f-8175-6583d13fbb44'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('262348fb-8dec-4b38-8c21-cb86a6ed7137'::uuid,'loadBilling','935629a2-5f21-4c5b-83aa-69d4f9731b05'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f4e55f6d-33e5-44d8-8736-5420e54371e0'::uuid,'loadReader','7d0b8803-605f-4c05-87f7-8486836dbced'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f4e55f6d-33e5-44d8-8736-5420e54371e0'::uuid,'loadBilling','849631ff-1f85-4a4f-849b-157d8e25504b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('330811e6-f0b4-40e1-8f8a-8755ddc253b3'::uuid,'loadReader','a6566302-d5e9-4ab3-8cf1-6d140baa052f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('330811e6-f0b4-40e1-8f8a-8755ddc253b3'::uuid,'loadBilling','d196b22d-ccb8-4e94-8552-e2af4b3e4477'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2b9d155b-8c72-4342-80cd-b2ff4c8a0eed'::uuid,'loadReader','ece299ff-f3fa-420b-8b0d-180662f7f941'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2b9d155b-8c72-4342-80cd-b2ff4c8a0eed'::uuid,'loadBilling','f52550c6-6b36-42ce-8219-0d67bc80a1b4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3b286330-2698-4b02-876c-c4ae27c83a4a'::uuid,'loadReader','fe710da9-52ab-4ea7-80ee-db1bb6e255c5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3b286330-2698-4b02-876c-c4ae27c83a4a'::uuid,'loadBilling','5407ba42-0779-4195-843f-744be608c643'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f5223de2-f52f-4627-8d4d-e1e31bdadef7'::uuid,'loadReader','8f26e77a-00c9-41b7-88e9-9c4f34e69878'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f5223de2-f52f-4627-8d4d-e1e31bdadef7'::uuid,'loadBilling','0db7c47c-9698-449c-8551-3f413a05a2af'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('76e23e75-61f9-4e6f-8869-5d0feb65be84'::uuid,'loadReader','32fde598-9fe3-4bb3-88d8-b54d96870e1c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('76e23e75-61f9-4e6f-8869-5d0feb65be84'::uuid,'loadBilling','3d529c5e-995d-4cda-8b2e-0224a03c5605'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('640d8ecc-c46c-4dd9-86f7-d3d980fadfe4'::uuid,'loadReader','b18e7a32-f1fc-49f8-8a92-f43fe3f79199'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('640d8ecc-c46c-4dd9-86f7-d3d980fadfe4'::uuid,'loadBilling','ae0ed4e1-10cf-4aa5-87f1-705dce979fb2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4dd0fc62-765d-4c46-8bfe-2ed2e24efdcb'::uuid,'loadReader','5a6b2305-0f6d-4bfa-893c-ee79c4ca3a2f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4dd0fc62-765d-4c46-8bfe-2ed2e24efdcb'::uuid,'loadBilling','6335428f-7cb1-499d-87de-8c30ef6e35bd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ae7f6746-1c35-4696-8679-c49e38f05e45'::uuid,'loadReader','25e47af1-48b3-4a17-8693-11cb44c39d70'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ae7f6746-1c35-4696-8679-c49e38f05e45'::uuid,'loadBilling','93406f34-b81b-47d7-8856-3deb9ccb44ea'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4b30616c-2425-4a93-8d84-1ea0322b3bef'::uuid,'loadReader','0e7c005c-1fcb-4ee4-841c-f562ee21bb76'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b30616c-2425-4a93-8d84-1ea0322b3bef'::uuid,'loadBilling','7ec7b938-1039-4dcb-84a4-e7b05c39c1c4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0fc63003-0360-4795-8e25-62b0b2cf8474'::uuid,'loadReader','b3e4789c-241f-429a-810d-e55eb6214f4f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0fc63003-0360-4795-8e25-62b0b2cf8474'::uuid,'loadBilling','dd522bd2-584e-4776-8b03-d67f7625a29a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d6d90e66-3c5b-4187-8061-0f4473cee4ae'::uuid,'loadReader','932e5342-bc06-4c01-8e2a-c86059a1a215'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d6d90e66-3c5b-4187-8061-0f4473cee4ae'::uuid,'loadBilling','802341e7-e011-44ff-8850-62781f6fe6f5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4226c892-c4cc-45d6-8598-049de2590112'::uuid,'loadReader','462f49ff-6959-450f-86e0-9dc3a4bd3e2b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4226c892-c4cc-45d6-8598-049de2590112'::uuid,'loadBilling','9b565413-4afc-4535-8876-b63d3a239d9a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('edfc1451-3736-496e-819d-565a65234d6c'::uuid,'loadReader','deb00c7b-a3f7-4714-81bd-fef704acb6f1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('edfc1451-3736-496e-819d-565a65234d6c'::uuid,'loadBilling','b33cc73a-ace9-42fc-82ed-d394c011b667'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('29f4da48-606f-49f6-8355-ba3bd3a5d2a9'::uuid,'loadReader','edf3f99e-5471-4cd0-862c-f4b177a1b033'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('29f4da48-606f-49f6-8355-ba3bd3a5d2a9'::uuid,'loadBilling','110c962d-c600-49c7-8e33-c371bf7de663'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('60b86217-f578-4777-812b-22257addeb81'::uuid,'loadReader','fa9540ae-5b20-48b4-82e8-0535d3faca59'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('60b86217-f578-4777-812b-22257addeb81'::uuid,'loadBilling','5b60db48-4b71-415b-8977-fac7f1800ea4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('931356c4-935a-4eaf-86e2-de9f82fe380d'::uuid,'loadReader','7d1a48ad-38c9-4c4f-8a5c-03bc35291ec1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('931356c4-935a-4eaf-86e2-de9f82fe380d'::uuid,'loadBilling','18f92d2c-2fe3-4b93-8761-cb061c8bf2f9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('81de924f-17f0-4cb2-82c6-5168eb3d5090'::uuid,'loadReader','84c6d53a-6740-4032-843a-0ebbde2abe3a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('81de924f-17f0-4cb2-82c6-5168eb3d5090'::uuid,'loadBilling','cfd85d64-bc02-4310-840a-9d4c7aa856dc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d6c7dd18-6056-41d6-8bc8-0f612785bde5'::uuid,'loadReader','55b0e0ca-2011-48de-8a81-098e8cab4fef'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d6c7dd18-6056-41d6-8bc8-0f612785bde5'::uuid,'loadBilling','04d1a378-bae4-482f-884a-0d1dc05f0b42'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ffcd7cc8-e694-474d-8458-46a6fbbb660d'::uuid,'loadReader','7e3f1a68-621f-457c-85d7-18196c0658fb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ffcd7cc8-e694-474d-8458-46a6fbbb660d'::uuid,'loadBilling','f9d0dd72-7ec5-4d4c-86f7-4d669f28a075'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('20bd1cce-69d4-4378-856b-87b942515040'::uuid,'loadReader','3cb1cc1c-297d-46c9-88db-edfcb83d1bb1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('20bd1cce-69d4-4378-856b-87b942515040'::uuid,'loadBilling','5a791a71-f84c-42d6-8cd2-342141f2b3e8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f1b8df22-5a61-44bb-8df6-14ed3945b1db'::uuid,'loadReader','0409496d-d25c-43f7-8b20-89a0db83cf2a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f1b8df22-5a61-44bb-8df6-14ed3945b1db'::uuid,'loadBilling','e9b39325-80b8-46c3-819f-699ff9115a07'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('437efe3f-4d10-4281-89b8-123f58a3984d'::uuid,'loadReader','518a6ac1-b0a2-4ee8-8c54-3a33ea081e31'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('437efe3f-4d10-4281-89b8-123f58a3984d'::uuid,'loadBilling','3bb4c6bc-7cf5-40c0-87fd-ffd75cda70b0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c9e8f5d5-9f73-4720-8d07-a2e5c4294ee6'::uuid,'loadReader','a1a5039e-e932-4236-8e0c-81452af6418e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c9e8f5d5-9f73-4720-8d07-a2e5c4294ee6'::uuid,'loadBilling','7721e132-4028-4434-8bca-1ec458f2e143'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7e3fb270-bdcd-4669-842f-916a9e9d74c0'::uuid,'loadReader','069a94f9-84dc-4c81-8914-ebdc480e5dce'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7e3fb270-bdcd-4669-842f-916a9e9d74c0'::uuid,'loadBilling','4fd662d6-afce-4380-8f19-93cfece607d2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('eeb4b65e-37fa-4759-89d5-e0ae335c1bd6'::uuid,'loadReader','a510730d-10d9-4f1d-8c28-b4ca3a3b0fc5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('eeb4b65e-37fa-4759-89d5-e0ae335c1bd6'::uuid,'loadBilling','ccbb3533-97e3-452b-83ca-a7d880118d28'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ab5fd6bf-db54-4222-8421-96f8b6ed4003'::uuid,'loadReader','ee174a38-fe11-4185-8b5e-76dd0ae8ac21'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ab5fd6bf-db54-4222-8421-96f8b6ed4003'::uuid,'loadBilling','79bd6140-a987-41f0-89a7-1ed3839a36e0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('931555b6-02c5-42ef-8650-8102ab999535'::uuid,'loadReader','6b4b92d2-19fc-4d61-838e-3933d86a123e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('931555b6-02c5-42ef-8650-8102ab999535'::uuid,'loadBilling','ae23c586-45df-420e-8ddb-87bcc9260c25'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9eed10c6-8063-445c-8520-108266220f52'::uuid,'loadReader','930ec089-2e2b-4ca9-85b4-4a6069a51703'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9eed10c6-8063-445c-8520-108266220f52'::uuid,'loadBilling','6565ef6c-7938-44e7-8198-d33f53524fcb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('37021e77-013f-4102-83c2-37e24f58bd38'::uuid,'loadReader','4a87e79c-1806-4932-8094-06f1ac0d5121'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('37021e77-013f-4102-83c2-37e24f58bd38'::uuid,'loadBilling','d01b9415-f365-49b9-8627-01c3dda5e461'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6a3138cc-10cc-4b02-89cd-7e29928c36f5'::uuid,'loadReader','28adb40a-a70d-4bc3-8cf7-87e75ac3d66d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6a3138cc-10cc-4b02-89cd-7e29928c36f5'::uuid,'loadBilling','3fe50150-b03e-4a82-8f32-a7d2502aa457'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('50916ab9-fc46-40c7-8e96-d9d908db5e78'::uuid,'loadReader','b85c889d-8f50-4710-8f6f-3167f71d98e6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('50916ab9-fc46-40c7-8e96-d9d908db5e78'::uuid,'loadBilling','c6e2ee94-83c5-4db4-89cd-d8a4fccb3a3b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('739d367d-17ec-443f-8f90-d7c536c05dea'::uuid,'loadReader','c1144506-3f88-47e0-822a-a04a0592cbb8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('739d367d-17ec-443f-8f90-d7c536c05dea'::uuid,'loadBilling','cf626f74-b8a0-429c-88b9-7c3814868f6b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c13bc441-e575-4408-8e04-3a55031803d3'::uuid,'loadReader','42d7ea60-f79c-4f81-86a7-4fbd055746b1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c13bc441-e575-4408-8e04-3a55031803d3'::uuid,'loadBilling','f40152a2-3985-4b12-8f72-af80f4fd0881'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('749f2bca-a0c2-4d17-8985-7cfe17790f1a'::uuid,'loadReader','c609d4c6-7c81-423e-8f45-b67163373bc6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('749f2bca-a0c2-4d17-8985-7cfe17790f1a'::uuid,'loadBilling','ed550f57-1c8d-43f3-8cd0-88579e913315'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('915ef487-45cb-4fad-8081-d52c5739f29e'::uuid,'loadReader','416bd03b-6792-4625-8892-648d2cad8a62'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('915ef487-45cb-4fad-8081-d52c5739f29e'::uuid,'loadBilling','c09d47d0-d1bc-4b38-848c-0b67e8aa1208'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('02d65368-34d1-46a8-85af-0dcc0698ce23'::uuid,'loadReader','86541974-aa75-4fe0-81fa-0c06c3237775'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('02d65368-34d1-46a8-85af-0dcc0698ce23'::uuid,'loadBilling','82c63f48-6dc3-4679-89ee-63f3426fe190'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b2bd17fc-3a28-4662-876d-2d20c38e55cc'::uuid,'loadReader','5834433e-9ca6-4d33-8add-a20fbd37d348'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b2bd17fc-3a28-4662-876d-2d20c38e55cc'::uuid,'loadBilling','454f8df6-1f4d-46b9-8949-380111c1211c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a0f4d798-a5e0-4e24-83c8-3e2de15ae301'::uuid,'loadReader','27bc0f58-e798-4743-80c0-718f10ae621e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a0f4d798-a5e0-4e24-83c8-3e2de15ae301'::uuid,'loadBilling','0ddc7e65-cfa7-4219-8dc8-5812a479c777'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3858cda9-9cb2-4970-886c-6a6e18866938'::uuid,'loadReader','6b668805-1ca8-49ad-803a-98ee436641a1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3858cda9-9cb2-4970-886c-6a6e18866938'::uuid,'loadBilling','39e084fc-b501-49de-86ec-81a7290daa7b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e74d0796-c5fc-43b6-8582-98e86bc2e68d'::uuid,'loadReader','badc78fe-e353-4b1f-8d42-679ce9aa62ef'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e74d0796-c5fc-43b6-8582-98e86bc2e68d'::uuid,'loadBilling','cf6a91d4-94f3-40a8-884f-a3110f849137'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('523cd390-7169-4fd5-856e-b608dcb10f17'::uuid,'loadReader','ff462ea8-b9d4-40e6-81a0-0c557de96598'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('523cd390-7169-4fd5-856e-b608dcb10f17'::uuid,'loadBilling','ec5085df-a903-4ad6-858d-4cab6f320fca'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8362e296-1d32-4692-8984-2a0e056c7d7b'::uuid,'loadReader','56980289-75c7-405f-8dce-f6264aa652ad'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8362e296-1d32-4692-8984-2a0e056c7d7b'::uuid,'loadBilling','63a6c53c-a9dd-4b9d-8bac-d6b44ded49ed'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('99598998-8e13-4e3e-87c5-cd33c6b5cddf'::uuid,'loadReader','ceb461dd-809b-432b-86a3-e56f1af51d99'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('99598998-8e13-4e3e-87c5-cd33c6b5cddf'::uuid,'loadBilling','d8dd441b-ed31-4760-8a87-91195d5fc915'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8fc43739-146b-437a-80d7-a8d6bba8971f'::uuid,'loadReader','a5ee260f-0d16-4761-81c2-f86740dc2671'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8fc43739-146b-437a-80d7-a8d6bba8971f'::uuid,'loadBilling','acd693b3-e991-4897-8072-b59aa0103859'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('01a50bff-87df-4913-80cd-0e00639452d6'::uuid,'loadReader','091a7c5a-0a73-434a-85b3-0f74041cd8d2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('01a50bff-87df-4913-80cd-0e00639452d6'::uuid,'loadBilling','d94a07af-358a-4bf2-8986-b635f1b74c12'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c8a4b8a4-ee97-4789-8669-8265e8d61ab8'::uuid,'loadReader','92e8efa1-afd5-4b52-82ac-f2e925482c20'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c8a4b8a4-ee97-4789-8669-8265e8d61ab8'::uuid,'loadBilling','2fc84457-13ca-4879-80fa-d76d3310cbbd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('42398919-acfa-4a74-8773-581c177b3abe'::uuid,'loadReader','d3bb1f1d-ab5a-42e6-84eb-f5c5c8e7a728'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('42398919-acfa-4a74-8773-581c177b3abe'::uuid,'loadBilling','9f6e7e7e-5a8e-48ce-8d71-0c459d4b970d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d10ec069-0546-4129-83c3-e0a4c564a65f'::uuid,'loadReader','6c0545d9-e57b-4227-806f-e216d1e9f18f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d10ec069-0546-4129-83c3-e0a4c564a65f'::uuid,'loadBilling','183cb6c7-5613-4fac-85f0-971beaede659'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7cc81afe-6389-4b0c-80fb-1e6830ccb63e'::uuid,'loadReader','41186eb5-5f88-4a8d-88a6-b5e595b2dff5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7cc81afe-6389-4b0c-80fb-1e6830ccb63e'::uuid,'loadBilling','2217ccac-9579-4004-8ac3-6d94f1264cb2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0ab923be-14ca-45e9-8148-63639dffa1f6'::uuid,'loadReader','ae1284f3-3f38-4fe2-8c9f-7020fcd9212b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0ab923be-14ca-45e9-8148-63639dffa1f6'::uuid,'loadBilling','d47cb2dd-f522-4e66-833b-786516d61ea0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c3011a41-3087-4f00-80d1-f268bf446e8f'::uuid,'loadReader','5153a4e6-58be-4746-839f-6735f4bb668f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c3011a41-3087-4f00-80d1-f268bf446e8f'::uuid,'loadBilling','dc466f40-6dfc-47d5-8e75-a30ee7cae663'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('95d80a45-2035-43c6-8ec0-bb5f741ad613'::uuid,'loadReader','de546237-a72a-4f5f-89d7-e55ea52397ee'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('95d80a45-2035-43c6-8ec0-bb5f741ad613'::uuid,'loadBilling','ff538064-4e99-4106-8631-fb71cc3ff3d1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('316cb9fb-dc48-46e2-840f-440f3822caea'::uuid,'loadReader','1964dc2e-163a-4a95-862c-b0bceaaf6d72'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('316cb9fb-dc48-46e2-840f-440f3822caea'::uuid,'loadBilling','5908fcd5-1968-4030-8605-a6702156396d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('13e472f1-6b70-4af9-8453-2d04bb35eff3'::uuid,'loadReader','3b056217-1079-454d-8dc2-87a7d63402b5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('13e472f1-6b70-4af9-8453-2d04bb35eff3'::uuid,'loadBilling','d41c4adb-bcda-4a4f-8168-559965586a55'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('81ba99f6-cd9e-468d-877d-6729f5bd93b6'::uuid,'loadReader','3dc3852a-40d8-4a46-8d66-4fd8c991ca4d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('81ba99f6-cd9e-468d-877d-6729f5bd93b6'::uuid,'loadBilling','1d77adc9-6efc-4606-8477-adaa91b31a31'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1e6d67f4-1cad-437e-804b-ccc398f93d80'::uuid,'loadReader','42cc08f2-ed58-45e5-878d-557551698fcb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1e6d67f4-1cad-437e-804b-ccc398f93d80'::uuid,'loadBilling','fc672ea1-0240-4c86-80d0-91598fb4b4ae'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a695322c-2b04-46ae-81b6-c12320ffbfe2'::uuid,'loadReader','00df72ff-54b7-449e-84fa-f5e7e83f3c64'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a695322c-2b04-46ae-81b6-c12320ffbfe2'::uuid,'loadBilling','f9e16c14-fbb4-4703-851d-9528b42d734a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('34f6e27c-af4a-4df6-8a35-93cbe9aaddc3'::uuid,'loadReader','b97f6024-b170-48e5-8b22-af69ec8333a3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('34f6e27c-af4a-4df6-8a35-93cbe9aaddc3'::uuid,'loadBilling','9f31dd9f-f75a-4892-8822-b71c21b8d840'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c9f045be-f9d4-41b9-875f-9271b9a50121'::uuid,'loadReader','6c853e4b-f799-4fc6-8397-8a1c72d2c48d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c9f045be-f9d4-41b9-875f-9271b9a50121'::uuid,'loadBilling','7809dd32-e54f-4ec0-81a6-dd7af4c20ba1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2a323d9b-f1ba-4a7e-87de-d026210d39f2'::uuid,'loadReader','68fc733e-8c59-4e05-8513-f4578d5ba6bd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2a323d9b-f1ba-4a7e-87de-d026210d39f2'::uuid,'loadBilling','a5ada1d6-d967-4d82-8f01-e68d31ed5381'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b581c62a-1214-4583-8da4-66df81db8b03'::uuid,'loadReader','d8fdc449-7140-4f46-8165-66a9041addc8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b581c62a-1214-4583-8da4-66df81db8b03'::uuid,'loadBilling','a2c55f9b-c1cf-45a5-8ee2-5a62c20f2964'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2fd04aa9-0a9f-4806-8465-75b2619b7183'::uuid,'loadReader','fe76ee3a-b331-44f0-89b4-c8a38e082538'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2fd04aa9-0a9f-4806-8465-75b2619b7183'::uuid,'loadBilling','09e89377-26a8-4ce9-8909-a2b92031c113'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c0ee9a8a-fcbc-4c9d-8e27-58b13ecf74c6'::uuid,'loadReader','5aed3908-95ab-46d4-84e8-a430487322ba'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c0ee9a8a-fcbc-4c9d-8e27-58b13ecf74c6'::uuid,'loadBilling','3bb843ac-c963-41e1-8301-2e3899a0b162'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d2e009bb-3a60-4d62-851f-c240723009ad'::uuid,'loadReader','61bad353-b538-4c59-86f8-1346aada2505'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d2e009bb-3a60-4d62-851f-c240723009ad'::uuid,'loadBilling','1e971932-35eb-4015-89c2-6ec1a1c61050'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8262fca2-c7b9-4385-87a1-b64f0d6e33ed'::uuid,'loadReader','52b158bd-9a61-4737-89b7-6fbf10828051'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8262fca2-c7b9-4385-87a1-b64f0d6e33ed'::uuid,'loadBilling','66cef39b-adb0-47bf-8dc8-5344725157bb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b14b5f74-aa84-4142-824e-922f73083f98'::uuid,'loadReader','d0a8906b-360a-4016-82b2-70389663ca45'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b14b5f74-aa84-4142-824e-922f73083f98'::uuid,'loadBilling','9315facb-925f-4979-855d-e3884cf08f80'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8c396d44-4291-4bef-895c-8dffc859a167'::uuid,'loadReader','39954892-0500-432e-85fa-795d6cb2b1c4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8c396d44-4291-4bef-895c-8dffc859a167'::uuid,'loadBilling','bc4fd2cf-7fa7-4bac-8bda-50542e64195f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c564b390-4351-4c8d-8f23-1b83d9c68ba9'::uuid,'loadReader','f993e2f4-5c86-4c86-8fe7-b845ff035e47'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c564b390-4351-4c8d-8f23-1b83d9c68ba9'::uuid,'loadBilling','a7a9b3b2-a5e2-4d6c-8bb5-3447afec9895'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9327d4cd-8848-4af8-86ab-8a3fca0c0957'::uuid,'loadReader','675fc8e2-b153-4d60-8ada-49a10212989e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9327d4cd-8848-4af8-86ab-8a3fca0c0957'::uuid,'loadBilling','57e0d074-3ad4-4ff1-8ab1-edc9e5d06e86'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bfc19d62-acae-4be3-8858-75342feebfb5'::uuid,'loadReader','0161d555-a1ec-4ae7-8d66-ef3c551935e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bfc19d62-acae-4be3-8858-75342feebfb5'::uuid,'loadBilling','08121ecf-6f9e-417d-8965-1d7655fb4d38'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f3e49c81-173d-486c-8c49-7efb17c69616'::uuid,'loadReader','74fc4cae-5f53-40b1-8d3f-4f62da7caac9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f3e49c81-173d-486c-8c49-7efb17c69616'::uuid,'loadBilling','6a414b58-b52a-4c56-8b5e-0f46cbff9187'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a93593b2-8004-4673-8409-0f715d194293'::uuid,'loadReader','fd67b8f5-5c36-4f01-8b10-f87028050f96'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a93593b2-8004-4673-8409-0f715d194293'::uuid,'loadBilling','975a557a-e874-44b3-85b3-dad22716fbf4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b2f22544-c113-4deb-8d52-1a633edbd4c9'::uuid,'loadReader','1f14b2e2-739b-4ce1-86bb-80cad49a5f51'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b2f22544-c113-4deb-8d52-1a633edbd4c9'::uuid,'loadBilling','0f031d3e-7346-4ab7-8d14-56486d7bdfdd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2f5d1306-aedb-40bd-83eb-02ef5153033a'::uuid,'loadReader','1bc8ebea-0958-427d-80d9-306e0db03166'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2f5d1306-aedb-40bd-83eb-02ef5153033a'::uuid,'loadBilling','ca06aa5b-f343-4adc-8197-d27ea8d43839'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4b1733d0-3112-457d-89a7-d6b0cbfbd18f'::uuid,'loadReader','4ea6b7b4-5839-4e96-84af-b188fafdf5cc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b1733d0-3112-457d-89a7-d6b0cbfbd18f'::uuid,'loadBilling','37fcc4ee-39a7-4708-8421-9e2719f2086f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0ea420ed-c76a-471d-867e-7df51bd93bda'::uuid,'loadReader','38a4593f-1f4b-4179-803c-6a2d2e48f5f3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0ea420ed-c76a-471d-867e-7df51bd93bda'::uuid,'loadBilling','2dd9a517-c236-4940-8816-163efcf4bb2a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bb01c171-434b-46a7-81ff-2506b1ab285c'::uuid,'loadReader','d145d97a-73fe-4753-877b-9fb890558f7c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bb01c171-434b-46a7-81ff-2506b1ab285c'::uuid,'loadBilling','9d461bc5-1a77-4a18-8260-d3635d90a175'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('69d6990c-a95a-479a-8ecf-5b19b2910849'::uuid,'loadReader','b4995d4f-8cb0-4ac3-8dfb-a0faaa9d8c3f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('69d6990c-a95a-479a-8ecf-5b19b2910849'::uuid,'loadBilling','1b2d420a-e104-4aa4-8f3e-bfab157efaa6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('99da003c-f792-4141-84a8-e93e9869a411'::uuid,'loadReader','f5bef156-ef9e-4f14-819d-90c124134c05'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('99da003c-f792-4141-84a8-e93e9869a411'::uuid,'loadBilling','d6e9f2bd-1676-494e-89a9-0c6fd3d91a37'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('394fc37f-b53c-4a34-84fb-0a30c06b4493'::uuid,'loadReader','4b73d37a-b7d8-47c2-8d93-c9896d1713c8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('394fc37f-b53c-4a34-84fb-0a30c06b4493'::uuid,'loadBilling','cff25a1b-faa7-47c5-8f8e-2026aee7b1fe'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d87765b6-a4bb-402c-810c-12a8b17d429f'::uuid,'loadReader','26be60be-0a6c-46db-8a5f-5bed30ce98c9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d87765b6-a4bb-402c-810c-12a8b17d429f'::uuid,'loadBilling','d444a1aa-b4ff-43f3-8510-20b773701fa8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('07cdbd9b-b6c8-41e7-8e82-9178a366822c'::uuid,'loadReader','75ed9ff5-9e03-4d8c-829f-25560dda6d1e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('07cdbd9b-b6c8-41e7-8e82-9178a366822c'::uuid,'loadBilling','6acd055e-740e-4b37-80b9-7a01e0c6f4a3'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('99a3feb9-b4e5-410f-87c9-3a3d6fb88ca0'::uuid,'loadReader','4470eb14-a4d8-4326-8e7d-b38207ee79b1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('99a3feb9-b4e5-410f-87c9-3a3d6fb88ca0'::uuid,'loadBilling','4c640cd0-1963-490f-812e-cbb19fc3f011'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3d9a79c4-7f89-4d30-8942-50b20fc0c5b1'::uuid,'loadReader','d736cd83-9a6c-46ff-8150-cd22a158a9c4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3d9a79c4-7f89-4d30-8942-50b20fc0c5b1'::uuid,'loadBilling','9120314f-3711-4531-87b3-062e2a6f337d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3a4b74bb-aa24-44ac-8f49-df21fc453694'::uuid,'loadReader','4b5f25f7-c4e2-4c2f-8ae6-e6d740f2bca2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3a4b74bb-aa24-44ac-8f49-df21fc453694'::uuid,'loadBilling','87a8d95f-19e9-40a8-8659-9d37bfb80c6d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6fb9a1c7-dc5e-418f-887e-a6682be21f66'::uuid,'loadReader','6e6943a1-de0b-4c91-8337-efe06b2cd439'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6fb9a1c7-dc5e-418f-887e-a6682be21f66'::uuid,'loadBilling','47518642-08ab-4261-872d-db4264f63458'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ab2cf896-f0b3-4830-818f-a4b24b303ad4'::uuid,'loadReader','d5e96cd3-e964-494b-8f9e-8a71b4c6a14b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ab2cf896-f0b3-4830-818f-a4b24b303ad4'::uuid,'loadBilling','e31c548e-6245-486a-8e21-61d03c3616ef'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('feca5daa-9db8-4b3f-8b4d-380a58ee0806'::uuid,'loadReader','c79786f3-93e8-423d-8cec-ae9559daa7da'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('feca5daa-9db8-4b3f-8b4d-380a58ee0806'::uuid,'loadBilling','2559d6b0-2c25-492c-899b-f9bbea50dbc6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5b225fc0-2ff8-4ea3-8c23-669ba3e004db'::uuid,'loadReader','58c49b09-a414-47f9-825f-ad3f8d652132'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5b225fc0-2ff8-4ea3-8c23-669ba3e004db'::uuid,'loadBilling','d23346a2-350b-43fc-80e3-451ac9de2bb7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1e19eb08-8464-43bf-8f03-1513b634343b'::uuid,'loadReader','bd1d39ab-d241-4267-8b51-edcbdbf76cbc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1e19eb08-8464-43bf-8f03-1513b634343b'::uuid,'loadBilling','a09238db-c911-408c-822e-839bf398cb22'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cad6ff75-93e4-4b4b-819e-8e4d3e3a3292'::uuid,'loadReader','2a323ffa-bffc-43ea-8712-1489e15f1ed3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cad6ff75-93e4-4b4b-819e-8e4d3e3a3292'::uuid,'loadBilling','4d225020-433f-4c89-8d33-1e9279135dbd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ccffcae7-325a-48c3-85cf-13d0a5d56c8f'::uuid,'loadReader','d2f26409-65bb-4b50-8003-c728a3e52de8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ccffcae7-325a-48c3-85cf-13d0a5d56c8f'::uuid,'loadBilling','64b86114-f790-43a3-8a49-6151d239050d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5fc1516b-2442-4699-8318-92bd0cbc89cf'::uuid,'loadReader','2ba07e29-36ca-47e6-8930-3e59425666e7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5fc1516b-2442-4699-8318-92bd0cbc89cf'::uuid,'loadBilling','9a72d048-88fe-48d0-88af-89bb8cbb8b4f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3a24c3bd-2038-477a-8862-9a70bd66d613'::uuid,'loadReader','64b49fff-f6f7-4f6c-8292-81f70c446248'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3a24c3bd-2038-477a-8862-9a70bd66d613'::uuid,'loadBilling','6909933d-d60a-4003-8b8f-310b34b17f72'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('93cd05c4-d57d-4a20-80d2-8d9e0f5125a8'::uuid,'loadReader','0e41518d-f60d-48e1-8832-f13fd6e367fc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('93cd05c4-d57d-4a20-80d2-8d9e0f5125a8'::uuid,'loadBilling','2c3e769e-0cf7-47ab-878e-d0a2db45355f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('949fb8e4-db6d-4ecf-84ae-4eff8435817c'::uuid,'loadReader','34d2b8fd-867d-4a2d-87de-8dc62edbe47e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('949fb8e4-db6d-4ecf-84ae-4eff8435817c'::uuid,'loadBilling','a92313a8-25ee-434d-8921-3da5e45e9118'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9770e99c-9ae3-4517-88ee-8d4f2adba39d'::uuid,'loadReader','b6dff072-e3d5-49bd-8afe-096ea0c45bb2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9770e99c-9ae3-4517-88ee-8d4f2adba39d'::uuid,'loadBilling','48df57b1-dbd5-4f1c-8cd2-0b16d6cd91e7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('254ef81c-71e6-48e3-8ff7-6f6172e82a17'::uuid,'loadReader','94b0c4bb-359e-4ca1-83d5-802e4cb35631'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('254ef81c-71e6-48e3-8ff7-6f6172e82a17'::uuid,'loadBilling','4bb936a0-8bc9-42f3-875a-1555b09575f7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a016abc6-6390-4db7-835c-12e0d4322f9e'::uuid,'loadReader','470f2fec-aa45-4bd4-8adc-084dfd4b2b0d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a016abc6-6390-4db7-835c-12e0d4322f9e'::uuid,'loadBilling','28091571-9b83-408a-850f-e4bc1911d498'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c66cb48d-0f45-416f-8db2-c1b658764e26'::uuid,'loadReader','0b63febe-07c4-42d2-8809-e234926e6db3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c66cb48d-0f45-416f-8db2-c1b658764e26'::uuid,'loadBilling','6b17b76a-9d57-4ee4-8481-34d9c8a25a32'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0311340c-051e-43ff-8647-fcc171d0ca2f'::uuid,'loadReader','6c8b24c4-1341-4b40-8501-b10b226d82a3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0311340c-051e-43ff-8647-fcc171d0ca2f'::uuid,'loadBilling','8bdca7d8-5e3c-4b1c-805c-47c3e418e83c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('833a4c20-a8eb-4164-8b7d-e905e22a5019'::uuid,'loadReader','2cf0a428-bf51-4662-8097-477872ade486'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('833a4c20-a8eb-4164-8b7d-e905e22a5019'::uuid,'loadBilling','6f6fe96d-5ea4-44b0-8fc1-cd324b8d4f89'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b8ba1030-87f2-4546-8420-b33ef3cc2df7'::uuid,'loadReader','ac8d5e40-d781-4e2b-8754-a2970e285a56'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b8ba1030-87f2-4546-8420-b33ef3cc2df7'::uuid,'loadBilling','9c8d57ab-9e9c-4194-8c04-26f95a93206d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('aaa6d5f8-ae3b-4c17-850b-04a12023b2d5'::uuid,'loadReader','e9cd5e0e-1529-4009-8bf6-90f613cbe5c9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('aaa6d5f8-ae3b-4c17-850b-04a12023b2d5'::uuid,'loadBilling','fae18e01-42fd-4204-8856-f63a52a37a8d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('60e951d4-6a72-4102-854d-0ce9ac9af52f'::uuid,'loadReader','04a52065-43a4-4cea-8f92-0991fb391c9d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('60e951d4-6a72-4102-854d-0ce9ac9af52f'::uuid,'loadBilling','1327d4cc-b771-4c14-8094-db83828d0d6d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0bb07e20-827d-4343-89fd-fef64cdfe849'::uuid,'loadReader','0d392093-861f-4c73-8aad-46a284b79b33'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0bb07e20-827d-4343-89fd-fef64cdfe849'::uuid,'loadBilling','4af55031-074c-4420-8bf9-df54f8adb38a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f1e63220-29f6-4585-8319-12f60cbbc308'::uuid,'loadReader','086ab1da-a973-436d-820f-ed3b18be171a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f1e63220-29f6-4585-8319-12f60cbbc308'::uuid,'loadBilling','90c39563-f191-4ed6-8c9b-d4757aaf59da'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6d1602e2-f145-4c7f-8ef1-1f2f8eb02243'::uuid,'loadReader','04b68503-b0c1-4395-8be2-a36711bb7dfb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6d1602e2-f145-4c7f-8ef1-1f2f8eb02243'::uuid,'loadBilling','11758a14-ab68-439a-8574-e6429ebaea78'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5da8518f-7444-4e56-8c43-26c00688ff9a'::uuid,'loadReader','7b879332-0050-49ad-8249-beafe60026a8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5da8518f-7444-4e56-8c43-26c00688ff9a'::uuid,'loadBilling','96a9b628-a0b2-462a-8e86-2495061fce8a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('00c1ebff-7fb6-4911-8238-f826aa3696aa'::uuid,'loadReader','a1fc05e8-b853-4497-8bd9-ecb6f5e45633'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('00c1ebff-7fb6-4911-8238-f826aa3696aa'::uuid,'loadBilling','00771e2d-ba35-4319-86d9-96b1877b16c7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b40d42d5-6633-409c-8d95-9ba9b27b2f21'::uuid,'loadReader','4058699a-48bd-42e6-8fe0-f5b6786886e8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b40d42d5-6633-409c-8d95-9ba9b27b2f21'::uuid,'loadBilling','1559f4ab-8af7-416b-839f-f9bce5fe2cf7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9212c28d-6383-4464-8916-c6606a2f54cf'::uuid,'loadReader','57153b0b-e727-4911-8f2c-456ed6dc3b81'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9212c28d-6383-4464-8916-c6606a2f54cf'::uuid,'loadBilling','0a0ff8b1-f55e-4154-8a14-22fbd2af1c95'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('147e1ce1-be19-4526-8b49-cb56fe8b498a'::uuid,'loadReader','a4cebe14-28a4-451a-8eeb-47adf4b739e9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('147e1ce1-be19-4526-8b49-cb56fe8b498a'::uuid,'loadBilling','1a1d147e-870c-47a3-8edf-80deb5417ab4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('32e300f5-02e3-4e13-8be5-961e98f74ce4'::uuid,'loadReader','ce6c4f52-5fa4-4da3-84c4-1d8c92acca7e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('32e300f5-02e3-4e13-8be5-961e98f74ce4'::uuid,'loadBilling','e3f0f8c5-0f62-4b86-8f9c-74b3ceca4a46'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5beeb777-fc79-41b7-8427-457b133e7c56'::uuid,'loadReader','4fe27d33-bf54-4a03-82fd-3e013d5b6e40'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5beeb777-fc79-41b7-8427-457b133e7c56'::uuid,'loadBilling','a3daa661-5bd4-4cfc-89d2-3810aeef8819'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f860fd39-8b0c-4956-8162-0dbe23a34087'::uuid,'loadReader','26620a57-fe51-4fdc-80d8-b588afc3c541'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f860fd39-8b0c-4956-8162-0dbe23a34087'::uuid,'loadBilling','685a28f5-a2a9-45bf-8fa7-b86d3b067ef4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1a398f44-2b21-4dda-8fe7-92dd6766577b'::uuid,'loadReader','47f698b7-ab43-4115-8633-16a3571d38c7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1a398f44-2b21-4dda-8fe7-92dd6766577b'::uuid,'loadBilling','3ef2ef71-65f9-45e6-8f6f-5c43ce308051'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('13ae1d32-0941-4d33-8d3c-b2ecda7511ff'::uuid,'loadReader','0a826101-bfa9-436e-8631-5ea8eb2852aa'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('13ae1d32-0941-4d33-8d3c-b2ecda7511ff'::uuid,'loadBilling','571c4b3a-d5d1-4d7c-8725-70c9a4c7d759'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b23de00a-f520-491d-81d0-ca0245c1d3f9'::uuid,'loadReader','d3ae4816-b521-453e-88d8-22b028421d82'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b23de00a-f520-491d-81d0-ca0245c1d3f9'::uuid,'loadBilling','6068d4ba-38ce-4624-84a5-090404b57c41'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6e133f0c-dd0c-43cc-85f8-a7b431124dd4'::uuid,'loadReader','0b8b5f9a-a11e-4510-89e1-d11b313f6c5f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6e133f0c-dd0c-43cc-85f8-a7b431124dd4'::uuid,'loadBilling','44e11d15-e6ee-4fa8-8e6b-2d47c34e4ff7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('19f45d27-20ff-4fb9-80f4-1d899855b219'::uuid,'loadReader','b7796462-4ac8-4d15-8731-eabcc6971f17'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('19f45d27-20ff-4fb9-80f4-1d899855b219'::uuid,'loadBilling','653c8f50-ff98-4e67-8ceb-6a82164a6003'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('37dc37d2-f4a2-438b-83ce-7d45e98039e9'::uuid,'loadReader','74bb1b53-fc22-47f1-8f70-b80c3eb1b73f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('37dc37d2-f4a2-438b-83ce-7d45e98039e9'::uuid,'loadBilling','bfe3e4e0-9bb7-4a3f-8613-b4ac19ad65df'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7f6240e4-3b1a-4531-85a8-029181fab5ff'::uuid,'loadReader','1998b53a-d96c-4787-8eb3-af25b05fcf81'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7f6240e4-3b1a-4531-85a8-029181fab5ff'::uuid,'loadBilling','b5e80f7f-44fb-42fc-8be4-e7d1f1632c29'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ea3e261b-c9f1-4e74-83b7-4a16e7891eae'::uuid,'loadReader','c3d7d6c1-af43-4b10-8401-b4de1d241ed9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ea3e261b-c9f1-4e74-83b7-4a16e7891eae'::uuid,'loadBilling','c8d2a9c4-81a4-4d84-86f3-8d18a183c454'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fcd700a4-188e-41aa-869b-a671e87768dd'::uuid,'loadReader','34b40575-59b1-423d-857d-26e4bf3c0cb7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fcd700a4-188e-41aa-869b-a671e87768dd'::uuid,'loadBilling','b5b51d7d-8461-4215-8556-ab7f1869dd59'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1e633b39-0f17-46d2-8128-42bb654e3a0d'::uuid,'loadReader','6cc5904e-8c89-43d2-89d0-a56686274328'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1e633b39-0f17-46d2-8128-42bb654e3a0d'::uuid,'loadBilling','e729bb55-08f9-4afb-8da0-b3e938658c78'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('936810bd-f3c5-4993-8e61-0011e1975ed7'::uuid,'loadReader','31665f67-0f94-4310-8dc7-761fdfca751d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('936810bd-f3c5-4993-8e61-0011e1975ed7'::uuid,'loadBilling','105d49de-818c-42da-8cbe-979bd28cde1d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('57f729b6-1120-49dd-8acf-51714ad590ba'::uuid,'loadReader','3fb4521d-53e8-4809-8782-6422f99b1a40'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('57f729b6-1120-49dd-8acf-51714ad590ba'::uuid,'loadBilling','7d150d34-2b37-40b7-8da3-29341eedec50'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('302de338-6855-4024-870c-bfdeb8a4b3e0'::uuid,'loadReader','89dc1d9e-c606-45ce-866a-c4a49d556303'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('302de338-6855-4024-870c-bfdeb8a4b3e0'::uuid,'loadBilling','fed76602-ea4e-4c05-868d-06c6a7c422f9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('44118a3d-c2b7-42a7-8eea-4d7cdf202866'::uuid,'loadReader','bfa9c919-4c3f-4ed8-8813-65e4cfaa9a6f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('44118a3d-c2b7-42a7-8eea-4d7cdf202866'::uuid,'loadBilling','6cd35adb-006e-4f7a-851d-4491310c8342'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d0a13f6b-94b0-4621-867f-7ca77b5ad71f'::uuid,'loadReader','cbc9b9de-d4a0-4d83-8fa3-033de9b66937'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d0a13f6b-94b0-4621-867f-7ca77b5ad71f'::uuid,'loadBilling','acebc95b-f5a3-4bc0-86d2-76d4de31d963'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d9ccbeaa-94e4-4e6c-8edb-7b195e841abf'::uuid,'loadReader','eb0c5869-44ea-4a49-8361-3c48e06f0d66'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d9ccbeaa-94e4-4e6c-8edb-7b195e841abf'::uuid,'loadBilling','a39626b4-c310-453c-8ef7-8cc940920683'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9fb86c44-d773-4167-8968-0dab883b63f2'::uuid,'loadReader','aa76e62b-abd7-46ea-828e-983d2a550736'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9fb86c44-d773-4167-8968-0dab883b63f2'::uuid,'loadBilling','f4ab1c6d-c225-4c45-85e5-22ebe580daf1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5f8b0ee1-80c8-46f2-8606-6ef4a3a1842f'::uuid,'loadReader','3590a337-c33a-437e-876d-897422c0e180'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5f8b0ee1-80c8-46f2-8606-6ef4a3a1842f'::uuid,'loadBilling','982b5a3a-21cf-4141-8fa4-a6bf95a4bed8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a7ce7ea3-f6ac-4f9c-8f99-5c6ffdd57f02'::uuid,'loadReader','eb8a1ab9-9714-4f6a-88d1-c26a3db6218c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a7ce7ea3-f6ac-4f9c-8f99-5c6ffdd57f02'::uuid,'loadBilling','9725fa75-f383-47c0-86ee-0ce2d491ad65'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4fa57b99-e8a2-4074-88c0-75fb4b1a5954'::uuid,'loadReader','cca1b592-a6d0-4666-8d3e-58f9d4ddaf72'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4fa57b99-e8a2-4074-88c0-75fb4b1a5954'::uuid,'loadBilling','d947945d-2026-46c4-8d57-d66c52322563'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('13f2596f-6552-446c-86f9-67d6384ce845'::uuid,'loadReader','6e9f3616-da5f-4cbe-8653-473103e17226'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('13f2596f-6552-446c-86f9-67d6384ce845'::uuid,'loadBilling','c3372fa7-4286-42e6-8d34-6282f50843cb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cc573650-9f31-4dc9-8273-50eed02bfff4'::uuid,'loadReader','74b1078e-2ed4-4077-8e92-f07c86ede919'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cc573650-9f31-4dc9-8273-50eed02bfff4'::uuid,'loadBilling','0342519a-8816-4e2b-8a6d-6e91952d0692'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4c5e8362-807d-41f9-8a1c-5731794d472a'::uuid,'loadReader','38434e91-72b2-40c5-8022-4df1e6c00812'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4c5e8362-807d-41f9-8a1c-5731794d472a'::uuid,'loadBilling','8b0f7136-48d6-4035-8b2b-e1a0e0044d7e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6841b66f-1aa8-481e-8541-5825ee7416f7'::uuid,'loadReader','872b4295-473f-44ca-8c49-8b2b6ae31450'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6841b66f-1aa8-481e-8541-5825ee7416f7'::uuid,'loadBilling','d57f82ec-08d4-484b-8c2a-30a259eea611'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b1c790f6-b269-4d98-88b0-952c667ef9cd'::uuid,'loadReader','c2d992dd-b762-4fb9-83af-c6af2362d9e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b1c790f6-b269-4d98-88b0-952c667ef9cd'::uuid,'loadBilling','2cdae9b0-8352-4bfd-849a-75aa935de762'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7fb6dabc-1575-415d-8344-e085b16ffeef'::uuid,'loadReader','e13cbeb2-faac-4ad6-8d60-f1d02485fc30'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7fb6dabc-1575-415d-8344-e085b16ffeef'::uuid,'loadBilling','e4f977b3-bcea-4a1f-8acb-2e7e082e322f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5ea58ffd-80e3-43cb-8f81-02b00f8daf08'::uuid,'loadReader','339487fe-14f7-4582-8e3a-70aad368966e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5ea58ffd-80e3-43cb-8f81-02b00f8daf08'::uuid,'loadBilling','5bb160c3-7b77-47cd-8ef7-1b97e6989270'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b686ed62-5d46-44b1-8d5d-ae786bd67b9c'::uuid,'loadReader','6a9cd157-edad-465c-8107-b474dc9cb73e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b686ed62-5d46-44b1-8d5d-ae786bd67b9c'::uuid,'loadBilling','71339379-8f18-4784-8cf7-209961177f50'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2c37251e-64b7-4fb1-820a-7a3388e1a746'::uuid,'loadReader','6407a320-6cc4-454a-803b-8741edd2ac3a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2c37251e-64b7-4fb1-820a-7a3388e1a746'::uuid,'loadBilling','4ca2a578-fa8d-48e7-8939-c22a1f3c73a6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e1aa09c3-7595-4666-869f-ad7e910259d7'::uuid,'loadReader','eb86be8a-0cce-4f4e-8bac-790f42e67f2e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e1aa09c3-7595-4666-869f-ad7e910259d7'::uuid,'loadBilling','f29d1990-80e1-4b98-88fc-ddb6f938bc8d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ecbbbb27-7057-41be-824e-ea07261ebc39'::uuid,'loadReader','823bfba1-3c18-4749-882a-dd5a03c0d5e6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ecbbbb27-7057-41be-824e-ea07261ebc39'::uuid,'loadBilling','453778b2-3814-470b-820c-7aa30ad11ae3'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('55d1a7e0-412f-42f0-848f-d941f2c50e98'::uuid,'loadReader','ef2f0041-dfbe-4b72-8952-8bc409621fc0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('55d1a7e0-412f-42f0-848f-d941f2c50e98'::uuid,'loadBilling','3942bca9-8936-4356-809f-35667be25575'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('78d1e0b0-b0c4-4e04-8a4c-32fc0bebb3fa'::uuid,'loadReader','da1e68ad-ce31-4280-8a40-35098c6793e5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('78d1e0b0-b0c4-4e04-8a4c-32fc0bebb3fa'::uuid,'loadBilling','f11f4ea7-af7b-4e82-87f2-ce8f99c677c0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('266410db-0000-41dd-8aae-2fbeb927e83f'::uuid,'loadReader','16d34468-40cd-4a9b-8b9b-8cf2b0e1436f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('266410db-0000-41dd-8aae-2fbeb927e83f'::uuid,'loadBilling','3f1d29cd-a8c5-4156-8d5c-0609e5271b56'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4b077dcf-ccb6-4672-8781-80883af3c4ff'::uuid,'loadReader','64d2b241-8bfd-4ede-80b7-528dc864be89'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4b077dcf-ccb6-4672-8781-80883af3c4ff'::uuid,'loadBilling','8f7cedf8-eb35-4cc7-8dc6-83f0b95c7df2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9e9dd40a-a8a5-4124-86ed-ca0bae8c8607'::uuid,'loadReader','67ea1c8d-1741-4bf8-8069-8d54a0d51098'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9e9dd40a-a8a5-4124-86ed-ca0bae8c8607'::uuid,'loadBilling','8aeda878-39dd-4feb-8312-ce806f68e40c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('409f5e5b-bb60-4df9-8be1-1ee91e6c827a'::uuid,'loadReader','36bba8d8-f15d-4458-8da8-1b0db8996276'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('409f5e5b-bb60-4df9-8be1-1ee91e6c827a'::uuid,'loadBilling','46a5c769-4ce2-4c44-887f-d46db9ab00dc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0ff3c42f-0fea-4dfb-8bd6-aa722d78055e'::uuid,'loadReader','9e2027ac-fb4f-4b56-8877-627ba19b5964'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0ff3c42f-0fea-4dfb-8bd6-aa722d78055e'::uuid,'loadBilling','fa684e20-ca15-4507-8789-4421f7ed4d47'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1dc844ee-48ad-49b1-8abf-707d45b55518'::uuid,'loadReader','fe47bf36-b1ed-4efb-8ade-48bf74503126'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1dc844ee-48ad-49b1-8abf-707d45b55518'::uuid,'loadBilling','41a97efd-7004-4580-858d-1e3ad72db865'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8f0fcc22-5322-4d09-80a0-b77b9e2dd380'::uuid,'loadReader','db3e1806-8787-4db9-8247-f1535ca8a3ef'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8f0fcc22-5322-4d09-80a0-b77b9e2dd380'::uuid,'loadBilling','1bbb846e-3824-48df-8d48-e84db9297154'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('57890d6b-3cc9-4f79-8a6d-229b3f2fa48c'::uuid,'loadReader','8627ac4e-d615-4f5d-8a80-fe3ddf98e1d2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('57890d6b-3cc9-4f79-8a6d-229b3f2fa48c'::uuid,'loadBilling','b673c8ea-50c1-4005-855a-82e880610f6d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0cfde7da-5253-4182-8ecc-74be62be4859'::uuid,'loadReader','6d05f767-36c2-4a2e-838d-02eef28299b6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0cfde7da-5253-4182-8ecc-74be62be4859'::uuid,'loadBilling','99683ce6-c20e-4b13-8001-6042e4997c81'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6a2ba1d8-37cd-437f-8d30-660714312bff'::uuid,'loadReader','9876c790-6cfd-4c96-8f8b-382cf4202c53'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6a2ba1d8-37cd-437f-8d30-660714312bff'::uuid,'loadBilling','bb7bf4e3-cd9c-493d-803c-29f7e5a6b52b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c4a9a550-4e27-42ca-8a2d-b47aacda512c'::uuid,'loadReader','6c2316c4-b5b6-4444-8666-172828e01663'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c4a9a550-4e27-42ca-8a2d-b47aacda512c'::uuid,'loadBilling','adc8af24-affe-4f85-89d2-10dac2e7ce9e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f8b198ed-bfea-4a20-8657-32685701a488'::uuid,'loadReader','7900494e-df0b-48ba-8b95-e2efba4e8571'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f8b198ed-bfea-4a20-8657-32685701a488'::uuid,'loadBilling','2e84a1a2-134a-4ad4-8ed6-788e8064dd5c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('660911e7-91db-4254-842c-14aa930a017d'::uuid,'loadReader','4eab2569-8654-4d58-81ab-6dc69aba1b0a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('660911e7-91db-4254-842c-14aa930a017d'::uuid,'loadBilling','d8203746-c2ce-49a9-85e2-96a390e8b185'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bdcea603-da09-474c-8a9d-1671a24ae396'::uuid,'loadReader','cd572e5d-2419-4d4a-8e0e-6c0137fbfcf4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bdcea603-da09-474c-8a9d-1671a24ae396'::uuid,'loadBilling','64ac5775-9082-4f01-8967-78cf15fddeca'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4502b65f-63ff-47b3-8ab6-861e98a96f4b'::uuid,'loadReader','ae50ceab-990e-49af-847d-c4021e674f48'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4502b65f-63ff-47b3-8ab6-861e98a96f4b'::uuid,'loadBilling','a3f2c5de-ad0a-455c-8b33-ddca5562f55a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ab26a0dd-4c12-4779-860f-94944de9477b'::uuid,'loadReader','9eeb9506-eb04-48c1-817d-0aba0948b7f0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ab26a0dd-4c12-4779-860f-94944de9477b'::uuid,'loadBilling','faf4337b-8406-4747-87e0-dda8f720590d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('99459e6b-6e52-4310-8ea0-4863af91f01d'::uuid,'loadReader','25e85423-737c-43ce-894d-552717da04bd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('99459e6b-6e52-4310-8ea0-4863af91f01d'::uuid,'loadBilling','7905b27a-8830-4d40-8cd0-9c2880dcb08c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('add74ea6-8cd3-4820-8f7c-010891a9e454'::uuid,'loadReader','4737b261-65d4-4136-8a90-4ec26a209227'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('add74ea6-8cd3-4820-8f7c-010891a9e454'::uuid,'loadBilling','b31e40c1-e015-408e-88cf-dcaacad36b9a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('586964c3-1775-485a-8f35-e90581742305'::uuid,'loadReader','5d2843f9-d018-4546-8451-87039ee3d8e0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('586964c3-1775-485a-8f35-e90581742305'::uuid,'loadBilling','1a6d216d-cdb2-48fe-8946-f8d97726fcb8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8131e4e3-9107-4df0-8b53-70e7de4980d0'::uuid,'loadReader','b000ac37-bcf7-49b5-8d83-4c6810f463ee'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8131e4e3-9107-4df0-8b53-70e7de4980d0'::uuid,'loadBilling','a8cf901e-28b3-4a65-8f31-c8d95be8986b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1ef7dff3-5c07-4f04-8ec5-cbc8884a338c'::uuid,'loadReader','8b09d699-b6cc-4c29-87d8-47ad86fd467e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1ef7dff3-5c07-4f04-8ec5-cbc8884a338c'::uuid,'loadBilling','1d17944f-2c92-455d-8e8a-3a277d69c135'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('34aab5af-8dfd-4153-8a88-c4d8b345b211'::uuid,'loadReader','81f01cc3-b715-4940-85b8-06b75e925d32'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('34aab5af-8dfd-4153-8a88-c4d8b345b211'::uuid,'loadBilling','ccf03a0f-d050-496f-8b3f-63375711ef06'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('80dca334-7ff7-46af-8069-0a9434cce68b'::uuid,'loadReader','4d4483f7-41fa-47dc-8b33-4a884bcd4eaf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('80dca334-7ff7-46af-8069-0a9434cce68b'::uuid,'loadBilling','2476d766-694b-43a7-8aa4-f4f75d3a13ae'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fd64d9e9-9654-407a-8b44-e39c4159560e'::uuid,'loadReader','89188962-5683-45c6-805d-d6ff160104f7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fd64d9e9-9654-407a-8b44-e39c4159560e'::uuid,'loadBilling','e5f82df5-ea23-4dc1-836f-efdf03692b09'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cf79df48-583c-4c54-8645-6b7c3d521132'::uuid,'loadReader','f15ca4b2-3b9b-40df-8c7d-e73b765394f9'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cf79df48-583c-4c54-8645-6b7c3d521132'::uuid,'loadBilling','5cb65beb-8535-4e1b-855c-61741922952e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fc7e4874-0ce0-4eab-83ad-315bceb564b0'::uuid,'loadReader','a2c29ebd-f4eb-4f1d-8f80-252ae6e09dca'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fc7e4874-0ce0-4eab-83ad-315bceb564b0'::uuid,'loadBilling','1b3f0ba8-8e43-4e15-8d76-d83317bef0a9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('215520a3-5129-4913-8e1d-6de045f48ed2'::uuid,'loadReader','d8f4ff83-b3dc-4cf6-8cf2-2457b10735b6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('215520a3-5129-4913-8e1d-6de045f48ed2'::uuid,'loadBilling','90acace8-bdde-49d3-896e-a4245e0b2c67'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b651a8b6-720b-4661-85c3-bb3c41784be8'::uuid,'loadReader','8833588c-9b51-4a8f-8c9c-d98a9230cd9f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b651a8b6-720b-4661-85c3-bb3c41784be8'::uuid,'loadBilling','ee39cebe-fb98-4126-8f15-9b2c82a4aa52'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('28669f9f-3401-41a0-80d6-b60f9d610828'::uuid,'loadReader','9d8c1e36-2954-40d9-8fb4-308b2504e548'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('28669f9f-3401-41a0-80d6-b60f9d610828'::uuid,'loadBilling','293f120d-81bf-4ec4-8aba-11961dc1bb6d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a4cd8cfb-8c8a-49a5-8d4a-edba46828d00'::uuid,'loadReader','bba16fa3-1b22-4ad8-8283-b2dfc4c09a06'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a4cd8cfb-8c8a-49a5-8d4a-edba46828d00'::uuid,'loadBilling','3b6c6888-abd5-445a-89fe-be650a975e35'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6fac7fe0-5267-4f17-8274-dcac808aaed1'::uuid,'loadReader','f21f6335-ad70-449d-8f67-19baad422ecd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6fac7fe0-5267-4f17-8274-dcac808aaed1'::uuid,'loadBilling','4180d2d1-766b-4948-8401-719762129cd7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bbeb2fc3-0f1f-45c0-8ccd-e8055b995ed4'::uuid,'loadReader','50fb74f0-eec4-4e3f-8290-d2c67b20318d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bbeb2fc3-0f1f-45c0-8ccd-e8055b995ed4'::uuid,'loadBilling','0fef1e10-4575-48f9-896a-884f51909f0d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e792ae16-4831-4a6f-8f55-dd187fa64f4b'::uuid,'loadReader','fcf99358-3407-454f-8a3f-178b2d13067c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e792ae16-4831-4a6f-8f55-dd187fa64f4b'::uuid,'loadBilling','f6f910c7-990a-47fb-8e43-bbeb806ddbed'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a732a2e8-fdfb-4afc-81e5-7f6f430f9fd9'::uuid,'loadReader','a88258c5-ddf3-40da-8e3c-a6d7020ac471'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a732a2e8-fdfb-4afc-81e5-7f6f430f9fd9'::uuid,'loadBilling','05862514-da92-4fe0-8aea-b9e5f4a6f8f8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3ec89122-3bd3-4ca3-8ae3-7bd66630d2b6'::uuid,'loadReader','a9f6ac1e-33c0-4d6b-8009-4c8954a54459'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3ec89122-3bd3-4ca3-8ae3-7bd66630d2b6'::uuid,'loadBilling','83b03b35-d14e-4944-861f-fd2fcb653c74'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a7d72eb0-1294-4356-889a-b12929eee5ce'::uuid,'loadReader','5de6ef83-fa93-4f90-804d-6a3f9a7c7f1f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a7d72eb0-1294-4356-889a-b12929eee5ce'::uuid,'loadBilling','366d4852-acd9-4acb-8111-2cbdeb55c85d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b3e81604-796b-4912-8ef9-10c7a542e993'::uuid,'loadReader','733802d3-d6a4-4d44-8565-d378f842d930'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b3e81604-796b-4912-8ef9-10c7a542e993'::uuid,'loadBilling','f7bbebeb-f672-4b04-80b7-dee3a1c25605'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3c16174f-89ae-4fe8-889f-44e0f5950e44'::uuid,'loadReader','f59c5c83-15c4-4f0e-8751-1664a9a66f55'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3c16174f-89ae-4fe8-889f-44e0f5950e44'::uuid,'loadBilling','bd27b06e-58d9-4008-8026-7c26c5093d28'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8231def5-92f0-4fef-8c11-7baff5f1e9c8'::uuid,'loadReader','e8d3f032-d5a9-4e6f-8fd4-e6389ebcbc2e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8231def5-92f0-4fef-8c11-7baff5f1e9c8'::uuid,'loadBilling','35a262c7-ea34-4d93-8496-64f0b500e891'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('459f9170-1822-45ec-8c7f-6727c1db6565'::uuid,'loadReader','5da6cc07-579e-4453-8f92-6104a8f6f619'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('459f9170-1822-45ec-8c7f-6727c1db6565'::uuid,'loadBilling','5e54aa6b-3cbd-4e84-848d-153adb61a506'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('310b6535-7643-4d73-85af-3898a03f56af'::uuid,'loadReader','0ca45b22-0883-4f1e-8725-44e24d1f40ea'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('310b6535-7643-4d73-85af-3898a03f56af'::uuid,'loadBilling','08a9b0e8-8d0f-455e-819d-acbf9d07a72b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('036d67fb-11a9-4851-8a21-374b9aa1637a'::uuid,'loadReader','4b774a9c-e6d6-4a1c-80e6-7b7f2759d319'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('036d67fb-11a9-4851-8a21-374b9aa1637a'::uuid,'loadBilling','b0cd72b6-08a0-4e98-8016-e620c1a5f2af'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6b1404e7-c28a-4ce6-8fe7-4af2bf138b03'::uuid,'loadReader','5b0c24dc-7e0e-48c7-8ed1-34f8185f1661'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6b1404e7-c28a-4ce6-8fe7-4af2bf138b03'::uuid,'loadBilling','75bb9cd9-0379-4eab-8fb9-e475f1b22fe0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e7afa70f-4f28-4ccb-81e6-51684e2cdab2'::uuid,'loadReader','e85bacd2-4413-44ec-8bf6-8a7b77bce8cf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e7afa70f-4f28-4ccb-81e6-51684e2cdab2'::uuid,'loadBilling','0298df3e-4fdc-4206-8d69-5e763cb1cfd7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('18a461f0-7542-4fc3-8f7a-f0a5bacb40bc'::uuid,'loadReader','9e7b0517-bacb-40c3-8e38-a02493d7090f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('18a461f0-7542-4fc3-8f7a-f0a5bacb40bc'::uuid,'loadBilling','e859fe2e-8232-4f12-8134-8cca82ee8f19'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4d7cc3f7-ce3b-4bba-89f6-6ca53a76db01'::uuid,'loadReader','662abab2-20a1-4c11-81db-9d7207a84b7f'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4d7cc3f7-ce3b-4bba-89f6-6ca53a76db01'::uuid,'loadBilling','0c7d28b9-a097-4126-8b0b-58f1255f6191'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3fb03146-7c8c-4f19-863f-023a0d1e405c'::uuid,'loadReader','93ee294e-c27a-4dbf-864f-ecc75650cb42'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3fb03146-7c8c-4f19-863f-023a0d1e405c'::uuid,'loadBilling','b8dee250-2c5f-495e-8c70-7ad99a4e771e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('639e85b3-68b6-4bb9-875d-ef190423ca99'::uuid,'loadReader','368c1437-6dfa-4d86-8a0a-f01b18947b25'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('639e85b3-68b6-4bb9-875d-ef190423ca99'::uuid,'loadBilling','92ea7669-fc92-4921-874e-dd6dfeb403d9'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('838d1903-32a3-4855-815b-b79f4687919b'::uuid,'loadReader','04b4ce0a-c525-4c0b-8aa2-eb469536fddb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('838d1903-32a3-4855-815b-b79f4687919b'::uuid,'loadBilling','9de2dec6-84c3-47ea-8f3f-1e87d708ee72'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cbaff433-33ac-48a4-8995-59d7e69c1921'::uuid,'loadReader','02ae5901-0755-4ff4-8fcd-efd388adda59'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cbaff433-33ac-48a4-8995-59d7e69c1921'::uuid,'loadBilling','ff2c3930-a169-4529-883b-93c9a746583c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1927a3a1-3759-4273-8bb9-de5508bd8147'::uuid,'loadReader','c7649dbc-952f-4d0e-89b7-3288b74463a7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1927a3a1-3759-4273-8bb9-de5508bd8147'::uuid,'loadBilling','5619dd0b-29c9-4402-8dd5-30884d996ae5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c4df6e8b-1400-480e-8d00-f44b39f17cbd'::uuid,'loadReader','1e234d82-af35-4cc9-8a4a-afeeba3fa07c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c4df6e8b-1400-480e-8d00-f44b39f17cbd'::uuid,'loadBilling','735a87a6-e058-460a-8fee-50fcb2464cf7'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a2d05520-1028-4c0e-809b-6f34c86bec32'::uuid,'loadReader','e4c37024-0c15-4b79-8378-6b82b1e90f04'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a2d05520-1028-4c0e-809b-6f34c86bec32'::uuid,'loadBilling','19892fa2-03c4-466a-8733-697b76e9df86'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('84ea827e-6d19-44cd-86f9-78105ce07903'::uuid,'loadReader','605ef686-9bb7-408a-80bd-d87f18b95c4a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('84ea827e-6d19-44cd-86f9-78105ce07903'::uuid,'loadBilling','710c8f11-102d-4cf9-8f84-a38ef6b9c5a6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f098d0f6-c382-4731-82cd-276e98fa9330'::uuid,'loadReader','87420d3a-bc3c-4ea4-81e5-14893c215f14'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f098d0f6-c382-4731-82cd-276e98fa9330'::uuid,'loadBilling','64a52f0b-54b6-4146-8075-c4585e8f9d3d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('98028273-419e-4a95-8b92-0a66ae687f4a'::uuid,'loadReader','5ffe6bd2-ffd3-4765-867c-79944736e09e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('98028273-419e-4a95-8b92-0a66ae687f4a'::uuid,'loadBilling','36470ed5-4589-4fd0-818c-712a5d4e0c6d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('97a5c5a6-d533-4d9c-8fb0-acfb9b018ad0'::uuid,'loadReader','22c6016c-837f-4fe9-8372-3d9183b2a93e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('97a5c5a6-d533-4d9c-8fb0-acfb9b018ad0'::uuid,'loadBilling','cb486fb0-f769-4406-8824-b7f830eef64e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c4b735d6-b68a-4fd9-8112-e6d5be80cef8'::uuid,'loadReader','ac35a5f2-ace0-4c08-809c-338d53f4dba3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c4b735d6-b68a-4fd9-8112-e6d5be80cef8'::uuid,'loadBilling','d784ff4e-5f3c-4ecf-89f6-93489b162e31'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e7a487c8-24fb-4b02-8412-4c80fa9ef0b5'::uuid,'loadReader','0c6fddc2-229b-4aa6-8d0c-b27c9c458156'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e7a487c8-24fb-4b02-8412-4c80fa9ef0b5'::uuid,'loadBilling','78743f43-0bcd-4929-8a29-7bdfa1c8c796'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('78e62e33-b6f1-4210-87d4-b35729995d8b'::uuid,'loadReader','76b7f9b7-5623-4ec2-8b6f-13765f6d30cf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('78e62e33-b6f1-4210-87d4-b35729995d8b'::uuid,'loadBilling','c13c15b4-91de-4abb-8071-5c3f9f3bc8bb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a626b497-ba02-47e4-813a-13424e4c0fce'::uuid,'loadReader','c6f41740-13a8-46c6-8fd5-791cef7f246a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a626b497-ba02-47e4-813a-13424e4c0fce'::uuid,'loadBilling','325aa776-c7b0-4835-8df6-16dab72b6f8a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d1c95d28-78c7-485c-8910-66fc4a708556'::uuid,'loadReader','b5a76f65-abb6-4554-8cbb-741cee27eb17'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d1c95d28-78c7-485c-8910-66fc4a708556'::uuid,'loadBilling','c5578d0f-01d8-4c87-8db0-a9a8920ad3bc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1dc055c2-d213-4571-8a90-67e749515b08'::uuid,'loadReader','62bf75d5-20b5-4880-8880-3363ecff032c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1dc055c2-d213-4571-8a90-67e749515b08'::uuid,'loadBilling','08d22ebd-e173-4a1e-8991-bace1037033e'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9d1e1333-d1f4-4e62-81f8-050d18850ff3'::uuid,'loadReader','244c4664-38d9-408e-891d-d65681e5f754'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9d1e1333-d1f4-4e62-81f8-050d18850ff3'::uuid,'loadBilling','452d05df-73fa-489d-8232-ad39a2af0087'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('edf0672f-f3d7-4940-847d-2096e138eeb5'::uuid,'loadReader','2ad686ee-27e4-45b2-850b-bd8658431746'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('edf0672f-f3d7-4940-847d-2096e138eeb5'::uuid,'loadBilling','9a1fdc27-b66b-4d96-86e3-3d870367d04d'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('198cf2cc-88dc-41e7-8106-02bac3796cc8'::uuid,'loadReader','a3b4aee7-52ba-4d84-87ef-ef12a751995d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('198cf2cc-88dc-41e7-8106-02bac3796cc8'::uuid,'loadBilling','40ef07da-c4ab-4258-86dc-fe6a9fe8ccf2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e680bc2d-d289-42a7-8bf6-e67ddbbec387'::uuid,'loadReader','e2a21a1a-f426-4877-8118-75c57bbe5504'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e680bc2d-d289-42a7-8bf6-e67ddbbec387'::uuid,'loadBilling','e6b7c451-c6dc-4a3f-89cf-b8f8f532daf8'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a51cbc51-b209-4e30-870d-3acb24d2d3a1'::uuid,'loadReader','a498d5b2-4153-4cd7-8752-e7c90d00c179'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a51cbc51-b209-4e30-870d-3acb24d2d3a1'::uuid,'loadBilling','57543835-e1cd-4264-8b7c-cec9f54173d6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b95544c7-f0dd-4337-85b7-525ea906e69c'::uuid,'loadReader','e32f5c16-bbeb-4afd-84c0-d4071e75d9a7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b95544c7-f0dd-4337-85b7-525ea906e69c'::uuid,'loadBilling','b9e51d13-48f1-418b-8b8b-e0c0d98c120c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('468ea760-da97-428b-8aa3-dff9d7cce110'::uuid,'loadReader','de850e96-1279-4529-847d-c305b40aa4a7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('468ea760-da97-428b-8aa3-dff9d7cce110'::uuid,'loadBilling','9655db78-662d-4acb-81a6-88cbd11fd4ad'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a6e2c988-a904-47ad-8640-eebeb4b313b3'::uuid,'loadReader','9bd637a3-3d81-4ee4-822f-f93532ddb322'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a6e2c988-a904-47ad-8640-eebeb4b313b3'::uuid,'loadBilling','02fa6a26-419d-48a1-818f-fc80bb0e0703'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('7db54ecc-d27a-4dd9-82b6-a73400f7b750'::uuid,'loadReader','f432c1b9-1513-48b6-88dc-9b4b67eea517'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('7db54ecc-d27a-4dd9-82b6-a73400f7b750'::uuid,'loadBilling','345c1e15-960b-4992-87bc-34b3bbf01353'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e6a48e36-6c71-4e67-8b1b-4c003893c293'::uuid,'loadReader','e534ac9e-f7f0-4daa-8e00-652c9473b03c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e6a48e36-6c71-4e67-8b1b-4c003893c293'::uuid,'loadBilling','e502ec26-f633-4824-8924-0a135b1bc6f1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('f14d7510-89e6-435f-8bed-369d871830ce'::uuid,'loadReader','5660d4a2-5ae7-4bd6-8013-f486d71348a3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('f14d7510-89e6-435f-8bed-369d871830ce'::uuid,'loadBilling','479bcc33-97b3-44c2-8631-3b35e45f2b37'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('6defeed4-41b6-44c1-89da-d0ed54a9c0f6'::uuid,'loadReader','a6a3977e-91cb-4311-8ee1-4c4286120787'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('6defeed4-41b6-44c1-89da-d0ed54a9c0f6'::uuid,'loadBilling','e40cbf09-fe36-4dd5-8a6f-5781770cac73'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('317da6d8-7cb7-4b4d-8d23-dd3016895594'::uuid,'loadReader','4ffabaa7-18da-49c1-8ada-e52c2a6428a1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('317da6d8-7cb7-4b4d-8d23-dd3016895594'::uuid,'loadBilling','62087556-1b29-4bf1-820d-0e7986ebe443'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('85841b12-3729-44bb-8886-c735c8017363'::uuid,'loadReader','956cbd46-1483-4f22-845e-933cc742de79'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('85841b12-3729-44bb-8886-c735c8017363'::uuid,'loadBilling','4c3a8bbb-5423-4383-8d27-cf20ecaf09b4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('dcb97f3d-e4b4-4c54-86e1-946690762242'::uuid,'loadReader','ea0921f8-15c3-4279-82e2-401b0314b69e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('dcb97f3d-e4b4-4c54-86e1-946690762242'::uuid,'loadBilling','db6804a1-aefc-470f-8ae7-e1901644be67'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('75cca57e-efdc-4489-8ece-b07b57b8cd13'::uuid,'loadReader','08196c1f-25ce-4ffd-888d-d09e8aff64bf'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('75cca57e-efdc-4489-8ece-b07b57b8cd13'::uuid,'loadBilling','40075205-86f0-445f-8304-2caec01dbac0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0e0318c7-1af2-4959-8917-5d89f101cbb1'::uuid,'loadReader','a9841339-ad67-4ecf-8586-f61130c1d666'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0e0318c7-1af2-4959-8917-5d89f101cbb1'::uuid,'loadBilling','d3391258-d56e-4012-80ef-1618775e4926'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('240cd482-66e5-4fd4-8e47-8de0c640d818'::uuid,'loadReader','275f2b1a-3639-45cb-8f5d-0b5ee859dcd4'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('240cd482-66e5-4fd4-8e47-8de0c640d818'::uuid,'loadBilling','9b507ca2-a24d-48a1-81d8-ec0426bf23e1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2f97a483-6100-4eb8-83cf-d58907269f4b'::uuid,'loadReader','6c75634e-7f69-41fb-8082-7786ce1d4cf0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2f97a483-6100-4eb8-83cf-d58907269f4b'::uuid,'loadBilling','feeba765-2ad4-4242-8d17-54733a7e0928'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d298a512-cf60-4a14-8500-c500e6844d9e'::uuid,'loadReader','3d8ab4c6-4c69-4937-8c05-9a135d84a593'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d298a512-cf60-4a14-8500-c500e6844d9e'::uuid,'loadBilling','432391ac-808d-4225-88ee-aeddc4ba70cc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c0a541b3-03af-4dc3-8e87-86bd378a299c'::uuid,'loadReader','1a11269f-7c1f-41be-8df2-3fc9ea7c326d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c0a541b3-03af-4dc3-8e87-86bd378a299c'::uuid,'loadBilling','f8762ec8-d8f5-43cf-8a4e-6f5429a5b286'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('cbcfe330-3b3a-4738-8720-f39c3a88692d'::uuid,'loadReader','2b4e5125-8695-44e6-80d6-b8a02be354d6'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('cbcfe330-3b3a-4738-8720-f39c3a88692d'::uuid,'loadBilling','d731ffad-0f94-48e7-8f0a-64d48fa48a27'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('938ce75a-0dd5-4cf4-8c60-ef2f281c07b4'::uuid,'loadReader','c81be7a9-684b-4b03-85b6-337ee6f2987a'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('938ce75a-0dd5-4cf4-8c60-ef2f281c07b4'::uuid,'loadBilling','fb0d15f4-6b4e-4c3b-8710-088adb0e38b6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('feb5c1de-b7fc-4deb-8143-7f129e9ffb01'::uuid,'loadReader','b6a6219e-fa30-4902-8fcd-f48dc970fd9c'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('feb5c1de-b7fc-4deb-8143-7f129e9ffb01'::uuid,'loadBilling','a8325895-5d87-45a2-8290-0b50c79490bc'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('86e1ecbb-f4b4-48bd-8e42-8e3782eee4d0'::uuid,'loadReader','b9262855-a55d-416e-856d-42c6ee9f805e'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('86e1ecbb-f4b4-48bd-8e42-8e3782eee4d0'::uuid,'loadBilling','48beb70a-2dcf-4d4b-8e2d-e6ce9a6c89e4'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b1eca120-085a-42da-8e47-a79f4ac6b45f'::uuid,'loadReader','31b0698a-fe05-4bed-8544-38ced40d63af'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b1eca120-085a-42da-8e47-a79f4ac6b45f'::uuid,'loadBilling','00b1d4e9-d792-4ed7-811b-a5e7c5ccb7f1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('405200c0-7556-431a-8c4e-cc819f093210'::uuid,'loadReader','f757dd89-0b6a-451d-850d-726965fa27f5'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('405200c0-7556-431a-8c4e-cc819f093210'::uuid,'loadBilling','f13f491b-5489-4f81-81f9-6868ff210614'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('64bdd06a-5fb7-4a2b-82b1-b2347d515209'::uuid,'loadReader','621720f7-7fe9-4edc-8d39-e76e62c2ae66'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('64bdd06a-5fb7-4a2b-82b1-b2347d515209'::uuid,'loadBilling','2a019707-73f1-45a2-8088-3f482a4f714c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c3ecd871-9d41-4d4a-8720-80eb19aaf324'::uuid,'loadReader','989e047c-3222-4452-873d-445e7018e044'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c3ecd871-9d41-4d4a-8720-80eb19aaf324'::uuid,'loadBilling','d6d91455-7dd5-400f-8535-43fb05da55c0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('0559c9a6-520f-4e57-84c4-b9e3c4581ef2'::uuid,'loadReader','79516918-cc39-459b-8292-13b9ce40d87b'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('0559c9a6-520f-4e57-84c4-b9e3c4581ef2'::uuid,'loadBilling','ce5c6857-8b38-43db-87fa-10452452645a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('a9279528-c43f-43d4-8299-909cbcbaf82b'::uuid,'loadReader','d2d7d0e6-0be2-478e-8190-9f9a4c1183a3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('a9279528-c43f-43d4-8299-909cbcbaf82b'::uuid,'loadBilling','2ad92520-b391-475b-8a84-e7816bab09b2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('b5eeaa9f-dafb-4617-8557-6b54b7c42b36'::uuid,'loadReader','77adda42-36de-47ef-8ad8-f1a29f65cad7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('b5eeaa9f-dafb-4617-8557-6b54b7c42b36'::uuid,'loadBilling','35113894-8965-4329-8266-4b6b77a28a5b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('2ed4ff88-cf01-48af-8998-4dbbb022506e'::uuid,'loadReader','0ede11fd-3218-4b15-8faa-653692058668'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('2ed4ff88-cf01-48af-8998-4dbbb022506e'::uuid,'loadBilling','2c21c2c8-7833-49de-8bfe-1903ba87f701'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('3eebe7ec-2d9b-489e-8df6-657c1961bce7'::uuid,'loadReader','975c8b4c-0ee6-4a03-8ca3-e128faf7938d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('3eebe7ec-2d9b-489e-8df6-657c1961bce7'::uuid,'loadBilling','970b37f2-23a5-4de7-8641-cd31fd4b454c'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('51c219c3-0238-4c39-8232-48eedaaea0d4'::uuid,'loadReader','e64cb51b-c4d3-4e96-8539-b3ef6a50aad7'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('51c219c3-0238-4c39-8232-48eedaaea0d4'::uuid,'loadBilling','11cf65d1-818b-48cc-8015-cc82dbf65e79'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('969e42a0-9bc1-4a46-8b13-232aeb5bb463'::uuid,'loadReader','a4680b45-4299-4f63-8d63-07077c1a33b1'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('969e42a0-9bc1-4a46-8b13-232aeb5bb463'::uuid,'loadBilling','12ea0061-ad6a-4174-8f80-c7033cad0bd0'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4f5d5e98-2357-4f15-8646-f12f20119309'::uuid,'loadReader','aada0105-b766-4e25-8875-b98e67b68883'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4f5d5e98-2357-4f15-8646-f12f20119309'::uuid,'loadBilling','181ece20-cc49-4f22-8d46-8e84a12301c1'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('4dfc0929-4978-4d65-8e90-ef6c62cad436'::uuid,'loadReader','9832fd38-2321-4de4-89a3-5688d77f7d09'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('4dfc0929-4978-4d65-8e90-ef6c62cad436'::uuid,'loadBilling','b421dc25-d491-4f67-8a4d-2eaee583aab2'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5125ca21-98ca-48f5-899f-8b928ca6f091'::uuid,'loadReader','f669a438-f6c3-4ff7-8ee4-6dd494791406'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5125ca21-98ca-48f5-899f-8b928ca6f091'::uuid,'loadBilling','9403f622-dd8c-4e26-8533-c8b448b7f823'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('bb4d1163-28f3-4e70-83a3-6331a6168f65'::uuid,'loadReader','c6c7e546-18e8-41fd-8698-50bcd92380ca'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('bb4d1163-28f3-4e70-83a3-6331a6168f65'::uuid,'loadBilling','6f9544e8-5d43-4224-8f3f-5ab7ecef5464'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c6704509-6c51-45e1-820a-5c9905cfcdd1'::uuid,'loadReader','2f1537ae-b6de-404f-89ec-dcdfb3209c59'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c6704509-6c51-45e1-820a-5c9905cfcdd1'::uuid,'loadBilling','ea177bb3-a35b-4cb4-85ea-046a3c6ab51b'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('465210cc-e716-48f4-84e9-79740566f77f'::uuid,'loadReader','5f75c0f5-9a5a-4283-8b9b-3f0b8252e585'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('465210cc-e716-48f4-84e9-79740566f77f'::uuid,'loadBilling','c25a6b0d-5d4d-40de-8792-08696d59ad1a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('eb5914e5-5d0f-4fad-8247-8d79bedaa3ba'::uuid,'loadReader','936eeecd-d6c0-40a8-8e74-1e0c54710633'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('eb5914e5-5d0f-4fad-8247-8d79bedaa3ba'::uuid,'loadBilling','160bcc45-7902-4ccd-8871-efbdc5d9e5bd'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('dceead08-5003-49d4-8d44-70a725cf7f9b'::uuid,'loadReader','0c7a454b-bd1d-44f9-8f34-b6ddb70a1bdb'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('dceead08-5003-49d4-8d44-70a725cf7f9b'::uuid,'loadBilling','c645b03c-4f47-48d9-8ecc-105a3ff561ab'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('9a647e15-10c4-4680-8ebf-8347f1b5fe35'::uuid,'loadReader','096ed9d5-bd1e-4d56-8029-d42bc13d7594'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('9a647e15-10c4-4680-8ebf-8347f1b5fe35'::uuid,'loadBilling','48ea9371-a938-446b-8c3e-9323d87fe1f6'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('5bef0e7a-0eca-4eac-8f6d-c87a46b1ddc2'::uuid,'loadReader','b7bac1e6-4ad3-4857-8c76-e7fde0d8bfd0'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('5bef0e7a-0eca-4eac-8f6d-c87a46b1ddc2'::uuid,'loadBilling','346c5e71-7582-4437-8f6c-8f7c61cdec63'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('e5cc18a4-2a0b-4234-8327-5cfa2e83d416'::uuid,'loadReader','9b4f31ee-28af-4fa5-88fc-bd6aca462824'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('e5cc18a4-2a0b-4234-8327-5cfa2e83d416'::uuid,'loadBilling','5f0c5730-7741-4bcf-8d5c-8b8de65c1658'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d3565966-a072-43b9-8ea4-e5f887839830'::uuid,'loadReader','5e3b0126-5f27-4f26-8b8b-2a795679a7cd'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d3565966-a072-43b9-8ea4-e5f887839830'::uuid,'loadBilling','b21a253e-90b0-478f-8e25-d137b272c07a'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('86e3d76b-0073-4956-84e8-e5e6d2e26288'::uuid,'loadReader','ecf90940-a64d-4459-8bd0-54c9251a6ad8'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('86e3d76b-0073-4956-84e8-e5e6d2e26288'::uuid,'loadBilling','80c89a0f-d1f0-4bdb-822d-bc5c8043b2fa'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('fbcb11bf-bff0-432a-89e1-26f0c2689adb'::uuid,'loadReader','05d2fe5d-43c2-4ba8-8e73-6b00329be009'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('fbcb11bf-bff0-432a-89e1-26f0c2689adb'::uuid,'loadBilling','7544efe1-e5c8-4aea-8708-432e7549da60'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('c88bcf7a-b720-49de-85b6-dde66e6015e0'::uuid,'loadReader','45817af3-e613-40f9-8527-7b91cba9ffa3'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('c88bcf7a-b720-49de-85b6-dde66e6015e0'::uuid,'loadBilling','147d3f1e-ca6a-472f-869b-c4f18d607a72'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('16fa14fa-0ad2-477c-88a2-e5e858bec250'::uuid,'loadReader','a3c9990e-1cd4-46f9-88ac-b85db3ba60e2'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('16fa14fa-0ad2-477c-88a2-e5e858bec250'::uuid,'loadBilling','979208f1-12d2-4c01-8eca-63bf44ff268f'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('8477935e-498d-4b80-8655-058740725522'::uuid,'loadReader','6dd7231c-85d6-4bdd-849a-70429c9e1ebc'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('8477935e-498d-4b80-8655-058740725522'::uuid,'loadBilling','a1b6551a-88fd-4459-8746-10d02d1d83fb'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('d156a4b7-e1de-439f-8a52-4fabcb956bc2'::uuid,'loadReader','c90a91c4-66f7-4889-8244-8c79e988e2af'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('d156a4b7-e1de-439f-8a52-4fabcb956bc2'::uuid,'loadBilling','14fed127-3256-4cf6-8b98-5e9a6f5bc0a5'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('ba344757-1a2a-4f17-88e8-d2cf71710e15'::uuid,'loadReader','af681f2c-26d6-4f29-8f08-547f9b651aff'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('ba344757-1a2a-4f17-88e8-d2cf71710e15'::uuid,'loadBilling','d2b8dded-0e7c-47fe-8281-6274c1d16956'::uuid,'["billing.read"]'::jsonb,false);
insert into w5_runtime_roles values('1c0e12f1-2fb0-43d6-89f7-a5ea5e60a3db'::uuid,'loadReader','d9a57dae-5965-42cd-82ac-7f89ad03062d'::uuid,'["analytics.view","workflow.process.view","crm.opportunities.view"]'::jsonb,false);
insert into w5_runtime_roles values('1c0e12f1-2fb0-43d6-89f7-a5ea5e60a3db'::uuid,'loadBilling','70137a81-188c-463d-83ba-dc478d8ce755'::uuid,'["billing.read"]'::jsonb,false);
do $$begin if exists(select 1 from w5_runtime_roles r cross join lateral jsonb_array_elements_text(r.permissions) p where not exists(select 1 from core.permissions c where c.code=p.value)) then
 raise exception 'REVIEWED_PERMISSION_MISSING';end if;end$$;
insert into core.roles(id,tenant_id,code,name,requires_mfa)
 select role_id,tenant_id,'w5_'||lower(role_key),'Synthetic Wave 5 '||role_key,requires_mfa from w5_runtime_roles;
insert into core.role_permissions(tenant_id,role_id,permission_code)
 select tenant_id,role_id,p.value from w5_runtime_roles cross join lateral jsonb_array_elements_text(permissions) p;
create temporary table w5_runtime_assignment_keys(tenant_id uuid,label text,role_key text);
insert into w5_runtime_assignment_keys values
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'proposer','reader'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'proposer','financeAnchor'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'proposer','proposer'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'approver','reader'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'approver','financeAnchor'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'approver','approver'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'executor','reader'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'executor','financeAnchor'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'executor','executor'),
 ('babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'billing-admin','billing');
insert into w5_runtime_assignment_keys select tenant_id,'foreign-member','foreignReader' from w5_runtime_scopes where key='foreign';
insert into w5_runtime_assignment_keys select s.tenant_id,a.label,case when a.label='billing-admin' then case when s.key='load-001' then 'billing' else 'loadBilling' end else 'loadReader' end
 from w5_runtime_scopes s cross join w5_runtime_accounts a where s.key like 'load-%' and a.label in('proposer','approver','executor','billing-admin');
insert into core.role_assignments(id,tenant_id,membership_id,role_id,legal_entity_id,branch_id,created_by)
 select md5(s.tenant_id::text||':'||k.label||':'||k.role_key)::uuid,s.tenant_id,md5(s.tenant_id::text||':'||k.label||':member')::uuid,r.role_id,
 case when k.role_key in('billing','loadBilling') then null else s.entity_id end,
 case when k.role_key in('billing','loadBilling','financeAnchor') then null else s.branch_id end,
 (select user_id from w5_runtime_accounts where label='billing-admin')
 from w5_runtime_assignment_keys k join w5_runtime_scopes s on s.tenant_id=k.tenant_id join w5_runtime_roles r on r.tenant_id=k.tenant_id and r.role_key=k.role_key;
insert into intelligence_control.synthetic_tenants(tenant_id,allowed)
 select tenant_id,true from w5_runtime_scopes where key in('runtime','load-001');
insert into intelligence_control.runtime_worker_scopes(runtime_id,tenant_id,legal_entity_id,branch_id,enabled,expires_at)
 values('778237e3-3d4e-4871-8cc9-e08b07b989c7'::uuid,'babe6c86-a764-4d3a-80a3-952a7c096c2c'::uuid,'caa2bb06-219a-47e9-8132-66d1271b0ffd'::uuid,'3813692c-f0de-4c69-8e34-d56cf54695b1'::uuid,true,statement_timestamp()+interval '24 hours');
-- Operator registration is separate from tenant membership. Fixed authority is
-- inserted immediately before the operator phase, using the separate script.
insert into intelligence_control.operators(actor_id,active,health_read,grant_manage)
 select user_id,true,true,true from w5_runtime_accounts where label='operator';
-- No integration destination, credential, HMAC key or operator grant is created
-- here. Bind exact receiver/host before review approval, register integrations
-- through real MFA, then issue the bounded operator grant through its MFA API.
select jsonb_build_object('tenants',(select count(*) from w5_runtime_scopes),'accounts',(select count(*) from w5_runtime_accounts),
 'memberships',(select count(*) from core.memberships where tenant_id in(select tenant_id from w5_runtime_scopes)),
 'roles',(select count(*) from w5_runtime_roles),'assignments',(select count(*) from w5_runtime_assignment_keys)) reviewed_counts;
commit;
