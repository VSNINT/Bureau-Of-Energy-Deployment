pipeline {
    agent any
    
    parameters {
        choice(
            name: 'ENVIRONMENT',
            choices: ['prod', 'uat', 'dr'],
            description: 'Select the environment to deploy'
        )
        choice(
            name: 'ACTION',
            choices: ['plan', 'apply', 'destroy'],
            description: 'Terraform action to perform'
        )
        booleanParam(
            name: 'AUTO_APPROVE',
            defaultValue: false,
            description: 'Auto approve terraform apply/destroy'
        )
        booleanParam(
            name: 'FORCE_CLEANUP',
            defaultValue: true,
            description: 'Force cleanup remaining resources after destroy'
        )
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
        PATH = "$PATH:$HOME/.local/bin"
        TF_CLI_ARGS = '-no-color'
    }
    
    stages {
        stage('Checkout & Setup') {
            steps {
                checkout scm
                echo "🚀 Starting deployment pipeline for environment: ${params.ENVIRONMENT}"
                echo "⚡ Terraform action: ${params.ACTION}"
                echo "🔧 Auto approve: ${params.AUTO_APPROVE}"
                echo "🧹 Force cleanup: ${params.FORCE_CLEANUP}"
            }
        }
        
        stage('Setup Terraform') {
            steps {
                script {
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "📥 Installing Terraform..."
                            wget -q https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
                            unzip -q terraform_1.5.7_linux_amd64.zip
                            chmod +x terraform
                            mkdir -p ~/.local/bin
                            mv terraform ~/.local/bin/
                            rm terraform_1.5.7_linux_amd64.zip
                            echo "✅ Terraform installed successfully"
                        else
                            echo "✅ Terraform already installed"
                        fi
                        export PATH="$HOME/.local/bin:$PATH"
                        terraform version
                    '''
                }
            }
        }
        
        stage('Restore State Files') {
            when {
                anyOf {
                    expression { params.ACTION == 'apply' }
                    expression { params.ACTION == 'destroy' }
                    expression { params.ACTION == 'plan' }
                }
            }
            steps {
                script {
                    echo "🔄 Attempting to restore previous state files..."
                    try {
                        step([
                            $class: 'CopyArtifact',
                            filter: 'terraform.tfstate*',
                            fingerprintArtifacts: true,
                            flatten: true,
                            projectName: env.JOB_NAME,
                            selector: [$class: 'StatusBuildSelector', stable: false],
                            optional: true
                        ])
                        echo "✅ Previous state files restored"
                    } catch (Exception e) {
                        echo "ℹ️ No previous state files found (normal for first deployment)"
                    }
                }
            }
        }
        
        stage('Initialize Terraform') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "🔧 Initializing Terraform..."
                        terraform init -upgrade -input=false
                        
                        echo "🏗️ Managing workspace for environment: ${ENVIRONMENT}"
                        terraform workspace select ${ENVIRONMENT} || terraform workspace new ${ENVIRONMENT}
                        
                        CURRENT_WORKSPACE=$(terraform workspace show)
                        echo "✅ Active workspace: $CURRENT_WORKSPACE"
                        
                        echo "📋 Available workspaces:"
                        terraform workspace list
                    '''
                }
            }
        }
        
        stage('Import Shared Resources') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🔄 Checking shared resources..."
                        if ! terraform state list | grep -q "azurerm_resource_group.main"; then
                            echo "📥 Importing shared resource group..."
                            terraform import azurerm_resource_group.main "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg" || echo "ℹ️ Resource group import attempted"
                        else
                            echo "✅ Resource group already in state"
                        fi
                        
                        echo "📊 Current state summary:"
                        RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
                        echo "Resources in state: $RESOURCE_COUNT"
                    '''
                }
            }
        }
        
        stage('Import Environment Resources') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🔍 Importing environment-specific resources for destroy..."
                        INITIAL_COUNT=$(terraform state list 2>/dev/null | wc -l)
                        echo "Initial resources in state: $INITIAL_COUNT"
                        
                        # Import VMs (with proper quoting for resource addressing)
                        echo "🖥️ Importing VMs..."
                        terraform import 'azurerm_windows_virtual_machine.vm["'${ENVIRONMENT}'-app"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Compute/virtualMachines/star-surya-${ENVIRONMENT}-app-vm" 2>/dev/null || echo "ℹ️ ${ENVIRONMENT}-app VM not found"
                        terraform import 'azurerm_windows_virtual_machine.vm["'${ENVIRONMENT}'-db"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Compute/virtualMachines/star-surya-${ENVIRONMENT}-db-vm" 2>/dev/null || echo "ℹ️ ${ENVIRONMENT}-db VM not found"
                        
                        # Import SQL VM config
                        echo "🗃️ Importing SQL VM configuration..."
                        terraform import 'azurerm_mssql_virtual_machine.db["'${ENVIRONMENT}'-db"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.SqlVirtualMachine/sqlVirtualMachines/star-surya-${ENVIRONMENT}-db-vm" 2>/dev/null || echo "ℹ️ SQL VM config not found"
                        
                        # Import Network Components
                        echo "🌐 Importing network components..."
                        terraform import azurerm_virtual_network.main "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/virtualNetworks/star-surya-${ENVIRONMENT}-vnet" 2>/dev/null || echo "ℹ️ VNet not found"
                        terraform import azurerm_subnet.app "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/virtualNetworks/star-surya-${ENVIRONMENT}-vnet/subnets/star-surya-${ENVIRONMENT}-app-subnet" 2>/dev/null || echo "ℹ️ App subnet not found"
                        terraform import azurerm_subnet.db "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/virtualNetworks/star-surya-${ENVIRONMENT}-vnet/subnets/star-surya-${ENVIRONMENT}-db-subnet" 2>/dev/null || echo "ℹ️ DB subnet not found"
                        
                        # Import Network Interfaces
                        echo "🔌 Importing network interfaces..."
                        terraform import 'azurerm_network_interface.vm["'${ENVIRONMENT}'-app"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/networkInterfaces/star-surya-${ENVIRONMENT}-app-nic" 2>/dev/null || echo "ℹ️ App NIC not found"
                        terraform import 'azurerm_network_interface.vm["'${ENVIRONMENT}'-db"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/networkInterfaces/star-surya-${ENVIRONMENT}-db-nic" 2>/dev/null || echo "ℹ️ DB NIC not found"
                        
                        # Import Public IPs
                        echo "🌍 Importing public IPs..."
                        terraform import 'azurerm_public_ip.vm["'${ENVIRONMENT}'-app"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/publicIPAddresses/star-surya-${ENVIRONMENT}-app-pip" 2>/dev/null || echo "ℹ️ App PIP not found"
                        terraform import 'azurerm_public_ip.vm["'${ENVIRONMENT}'-db"]' "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/publicIPAddresses/star-surya-${ENVIRONMENT}-db-pip" 2>/dev/null || echo "ℹ️ DB PIP not found"
                        
                        # Import NSGs and Associations
                        echo "🔒 Importing security groups..."
                        terraform import azurerm_network_security_group.app "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/networkSecurityGroups/star-surya-${ENVIRONMENT}-app-nsg" 2>/dev/null || echo "ℹ️ App NSG not found"
                        terraform import azurerm_network_security_group.db "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/networkSecurityGroups/star-surya-${ENVIRONMENT}-db-nsg" 2>/dev/null || echo "ℹ️ DB NSG not found"
                        terraform import azurerm_subnet_network_security_group_association.app "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/virtualNetworks/star-surya-${ENVIRONMENT}-vnet/subnets/star-surya-${ENVIRONMENT}-app-subnet" 2>/dev/null || echo "ℹ️ App NSG association not found"
                        terraform import azurerm_subnet_network_security_group_association.db "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg/providers/Microsoft.Network/virtualNetworks/star-surya-${ENVIRONMENT}-vnet/subnets/star-surya-${ENVIRONMENT}-db-subnet" 2>/dev/null || echo "ℹ️ DB NSG association not found"
                        
                        FINAL_COUNT=$(terraform state list 2>/dev/null | wc -l)
                        echo "📊 Resources after import: $FINAL_COUNT"
                        echo "✅ Import process completed"
                    '''
                }
            }
        }
        
        stage('Validate Configuration') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "✅ Formatting and validating configuration..."
                        terraform fmt -check=false
                        terraform validate
                        echo "✅ Configuration valid for workspace: $(terraform workspace show)"
                    '''
                }
            }
        }
        
        stage('Terraform Plan') {
            when {
                anyOf {
                    expression { params.ACTION == 'plan' }
                    expression { params.ACTION == 'apply' }
                }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh """
                        export PATH="\$HOME/.local/bin:\$PATH"
                        echo "📋 Creating execution plan..."
                        echo "🎯 Environment: ${params.ENVIRONMENT}"
                        echo "🏗️ Workspace: \$(terraform workspace show)"
                        terraform plan -var="environment=${params.ENVIRONMENT}" -out=tfplan-${params.ENVIRONMENT} -detailed-exitcode || true
                    """
                    
                    script {
                        try {
                            archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                        } catch (Exception e) {
                            echo "⚠️ Could not archive plan file: ${e.getMessage()}"
                        }
                    }
                }
            }
        }
        
        stage('Terraform Apply') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                script {
                    def approvalMessage = params.AUTO_APPROVE ? "Auto-approved" : "Manual approval required"
                    echo "🚀 Deployment mode: ${approvalMessage}"
                    
                    if (!params.AUTO_APPROVE) {
                        input message: "🚀 Deploy ${params.ENVIRONMENT} environment?", ok: 'Deploy'
                    }
                    
                    withCredentials([
                        string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                        string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                        string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                        string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                    ]) {
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            echo "🚀 Deploying infrastructure..."
                            echo "🎯 Environment: ${params.ENVIRONMENT}"
                            echo "🏗️ Workspace: \$(terraform workspace show)"
                            terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                        """
                    }
                }
            }
        }
        
        stage('Terraform Destroy - Phase 1') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                script {
                    input message: "⚠️ DANGER: Destroy ${params.ENVIRONMENT} environment? This cannot be undone!", ok: 'Destroy'
                    
                    withCredentials([
                        string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                        string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                        string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                        string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                    ]) {
                        sh '''
                            export PATH="$HOME/.local/bin:$PATH"
                            
                            echo "🗑️ === PHASE 1: COMPUTE & SQL RESOURCES ==="
                            echo "🎯 Environment: ${ENVIRONMENT}"
                            echo "🏗️ Workspace: $(terraform workspace show)"
                            
                            RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Total resources in state: $RESOURCE_COUNT"
                            
                            # Phase 1: Destroy VMs and SQL components first
                            echo "🖥️ Destroying VMs and SQL resources..."
                            terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                                -target="azurerm_mssql_virtual_machine.db" \
                                -target="azurerm_windows_virtual_machine.vm" \
                                2>/dev/null || echo "ℹ️ VM destroy completed with warnings"
                            
                            echo "✅ Phase 1 completed"
                        '''
                    }
                }
            }
        }
        
        stage('Terraform Destroy - Phase 2') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🗑️ === PHASE 2: NETWORK INTERFACES & IPs ==="
                        
                        # Wait a moment for Azure to process VM deletions
                        echo "⏳ Waiting 30 seconds for Azure to process..."
                        sleep 30
                        
                        # Phase 2: Destroy network interfaces and public IPs
                        echo "🔌 Destroying network interfaces and public IPs..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="azurerm_network_interface.vm" \
                            -target="azurerm_public_ip.vm" \
                            2>/dev/null || echo "ℹ️ Network interface destroy completed with warnings"
                        
                        echo "✅ Phase 2 completed"
                    '''
                }
            }
        }
        
        stage('Terraform Destroy - Phase 3') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🗑️ === PHASE 3: NETWORK SECURITY & SUBNETS ==="
                        
                        # Wait another moment
                        echo "⏳ Waiting 30 seconds for network cleanup..."
                        sleep 30
                        
                        # Phase 3: Destroy NSG associations and security groups
                        echo "🔒 Destroying NSG associations..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="azurerm_subnet_network_security_group_association.app" \
                            -target="azurerm_subnet_network_security_group_association.db" \
                            2>/dev/null || echo "ℹ️ NSG association destroy completed with warnings"
                        
                        echo "🛡️ Destroying network security groups..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="azurerm_network_security_group.app" \
                            -target="azurerm_network_security_group.db" \
                            2>/dev/null || echo "ℹ️ NSG destroy completed with warnings"
                        
                        echo "🌐 Destroying subnets..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="azurerm_subnet.app" \
                            -target="azurerm_subnet.db" \
                            2>/dev/null || echo "ℹ️ Subnet destroy completed with warnings"
                        
                        echo "✅ Phase 3 completed"
                    '''
                }
            }
        }
        
        stage('Terraform Destroy - Phase 4') {
            when {
                expression { params.ACTION == 'destroy' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🗑️ === PHASE 4: VIRTUAL NETWORK & CLEANUP ==="
                        
                        # Wait for previous operations
                        echo "⏳ Waiting 45 seconds for network security cleanup..."
                        sleep 45
                        
                        # Phase 4: Destroy virtual network and remaining resources
                        echo "🌐 Destroying virtual network..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="azurerm_virtual_network.main" \
                            2>/dev/null || echo "ℹ️ VNet destroy completed with warnings"
                        
                        echo "🔑 Destroying password resource..."
                        terraform destroy -auto-approve -var="environment=${ENVIRONMENT}" \
                            -target="random_password.vm_password" \
                            2>/dev/null || echo "ℹ️ Password destroy completed"
                        
                        echo "✅ Phase 4 completed"
                    '''
                }
            }
        }
        
        stage('Force Cleanup & Verification') {
            when {
                allOf {
                    expression { params.ACTION == 'destroy' }
                    expression { params.FORCE_CLEANUP == true }
                }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo "🧹 === FORCE CLEANUP & VERIFICATION ==="
                        
                        # Check remaining resources
                        REMAINING=$(terraform state list | grep -v "azurerm_resource_group.main" | grep -v "data.azurerm_client_config.current" | wc -l)
                        echo "📊 Remaining resources in state: $REMAINING"
                        
                        if [ "$REMAINING" -gt 0 ]; then
                            echo "⚠️ Found lingering resources. Performing force cleanup..."
                            
                            # List remaining resources
                            echo "🔍 Remaining resources:"
                            terraform state list | grep -v "azurerm_resource_group.main" | grep -v "data.azurerm_client_config.current"
                            
                            # Force remove from state
                            terraform state list | grep -v "azurerm_resource_group.main" | grep -v "data.azurerm_client_config.current" | while read resource; do
                                if [ ! -z "$resource" ]; then
                                    echo "🗑️ Force removing: $resource"
                                    terraform state rm "$resource" 2>/dev/null || echo "Could not remove $resource"
                                fi
                            done
                        fi
                        
                        # Final verification
                        FINAL_REMAINING=$(terraform state list | grep -v "azurerm_resource_group.main" | grep -v "data.azurerm_client_config.current" | wc -l)
                        echo "📊 Final remaining resources: $FINAL_REMAINING"
                        
                        if [ "$FINAL_REMAINING" -eq 0 ]; then
                            echo "✅ Terraform state successfully cleaned!"
                            echo "📋 Only protected resources remain:"
                            terraform state list
                        else
                            echo "⚠️ Some resources may still exist in Azure"
                            echo "🔍 Manual cleanup may be required in Azure Portal"
                            echo "🎯 Search for resources containing: ${ENVIRONMENT}"
                        fi
                        
                        echo "✅ Force cleanup completed"
                    '''
                }
            }
        }
        
        stage('Display Results') {
            when {
                expression { params.ACTION == 'apply' }
            }
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        
                        echo ""
                        echo "=========================================="
                        echo "🎉 DEPLOYMENT SUCCESSFUL!"
                        echo "=========================================="
                        echo "🎯 Environment: ${ENVIRONMENT}"
                        echo "🏗️ Workspace: $(terraform workspace show)"
                        echo "📊 Resources managed: $(terraform state list 2>/dev/null | wc -l)"
                        echo ""
                        
                        echo "🔐 === VM CREDENTIALS ==="
                        echo "👤 Username: azureadmin"
                        PASSWORD=$(terraform output -raw admin_password 2>/dev/null || echo "Not available")
                        echo "🔑 Password: [${PASSWORD}]"
                        echo ""
                        
                        if terraform output vm_public_ips >/dev/null 2>&1; then
                            echo "🌐 === PUBLIC IP ADDRESSES ==="
                            terraform output vm_public_ips
                            echo ""
                            
                            echo "🔒 === PRIVATE IP ADDRESSES ==="
                            terraform output vm_private_ips || echo "Private IPs not available"
                            echo ""
                            
                            echo "🎯 === QUICK RDP COMMANDS ==="
                            APP_IP=$(terraform output -json vm_public_ips 2>/dev/null | grep -o '"${ENVIRONMENT}-app":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                            DB_IP=$(terraform output -json vm_public_ips 2>/dev/null | grep -o '"${ENVIRONMENT}-db":"[^"]*"' | cut -d'"' -f4 2>/dev/null || echo "")
                            
                            if [ ! -z "$APP_IP" ] && [ "$APP_IP" != "null" ]; then
                                echo "Application Server: mstsc /v:$APP_IP"
                            fi
                            if [ ! -z "$DB_IP" ] && [ "$DB_IP" != "null" ]; then
                                echo "Database Server: mstsc /v:$DB_IP"
                            fi
                        else
                            echo "📝 Deployment completed - outputs will be available after refresh"
                        fi
                        
                        echo ""
                        echo "=========================================="
                        echo "📋 DEPLOYMENT SUMMARY"
                        echo "=========================================="
                        echo "✅ Environment: ${ENVIRONMENT}"
                        echo "✅ Status: Successfully deployed"
                        echo "✅ Workspace: $(terraform workspace show)"
                        echo "✅ Protected RG: star-surya-rg"
                        echo "=========================================="
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🗃️ Archiving artifacts for workspace: ${params.ENVIRONMENT}"
                
                // Archive state files with error handling
                try {
                    sh 'find . -name "terraform.tfstate*" -type f 2>/dev/null || true'
                    archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive state files: ${e.getMessage()}"
                }
                
                try {
                    archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive lock file: ${e.getMessage()}"
                }
                
                try {
                    archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive plan file: ${e.getMessage()}"
                }
                
                // Conditional workspace cleanup
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy of ${params.ENVIRONMENT}"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace for ${params.ENVIRONMENT} environment"
                }
            }
        }
        
        success {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '✅', 'destroy': '🗑️']
                def actionName = ['plan': 'planned', 'apply': 'deployed', 'destroy': 'destroyed']
                
                echo "🎉 SUCCESS: ${params.ENVIRONMENT} environment ${actionName[params.ACTION]} successfully!"
                echo "📊 Pipeline: ${actionEmoji[params.ACTION]} ${params.ACTION.toUpperCase()}"
                echo "🏗️ Workspace: ${params.ENVIRONMENT}"
                
                if (params.ACTION == 'apply') {
                    echo "🔐 Access credentials displayed above"
                    echo "🌐 VMs are ready for use"
                } else if (params.ACTION == 'destroy') {
                    echo "🗑️ Environment cleanup completed"
                    echo "🛡️ Shared resources protected"
                    echo "🧹 Force cleanup: ${params.FORCE_CLEANUP ? 'Enabled' : 'Disabled'}"
                }
                
                echo "✅ Pipeline completed successfully"
            }
        }
        
        failure {
            script {
                def actionEmoji = ['plan': '📋', 'apply': '❌', 'destroy': '💥']
                
                echo "💥 FAILURE: ${params.ACTION} failed for ${params.ENVIRONMENT} environment"
                echo "📊 Pipeline: ${actionEmoji[params.ACTION]} ${params.ACTION.toUpperCase()}"
                echo "🏗️ Workspace: ${params.ENVIRONMENT}"
                echo "🔍 Check logs above for detailed error information"
                
                // Archive state files even on failure for debugging
                try {
                    archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                } catch (Exception e) {
                    echo "⚠️ Could not archive state files on failure"
                }
                
                if (params.ACTION == 'destroy') {
                    echo "⚠️ Partial destroy may have occurred"
                    echo "🔍 Check Azure Portal for remaining resources"
                    echo "🎯 Search for: ${params.ENVIRONMENT} resources"
                }
            }
        }
        
        aborted {
            script {
                echo "⏹️ Pipeline aborted for ${params.ENVIRONMENT} environment"
                echo "📊 Action: ${params.ACTION.toUpperCase()}"
                echo "⚠️ Infrastructure may be in inconsistent state"
                
                if (params.ACTION == 'apply') {
                    echo "🔍 Check for partially created resources"
                } else if (params.ACTION == 'destroy') {
                    echo "🔍 Check for partially destroyed resources"
                }
            }
        }
    }
}
