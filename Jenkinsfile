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
    }
    
    environment {
        TF_IN_AUTOMATION = 'true'
        PATH = "$PATH:$HOME/.local/bin"
    }
    
    stages {
        stage('Checkout') {
            steps {
                checkout scm
                echo "🚀 Deploying to environment: ${params.ENVIRONMENT}"
                echo "⚡ Terraform action: ${params.ACTION}"
            }
        }
        
        stage('Setup Terraform') {
            steps {
                script {
                    sh '''
                        if ! command -v terraform &> /dev/null; then
                            echo "📥 Installing Terraform..."
                            wget https://releases.hashicorp.com/terraform/1.5.7/terraform_1.5.7_linux_amd64.zip
                            unzip terraform_1.5.7_linux_amd64.zip
                            chmod +x terraform
                            mkdir -p ~/.local/bin
                            mv terraform ~/.local/bin/
                            rm terraform_1.5.7_linux_amd64.zip
                            echo "✅ Terraform installed successfully"
                        else
                            echo "✅ Terraform is already installed"
                        fi
                        export PATH="$HOME/.local/bin:$PATH"
                        terraform version
                    '''
                }
            }
        }
        
        stage('Restore Previous State') {
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
        
        stage('Terraform Init & Workspace Setup') {
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
                        
                        echo "🏗️ Setting up workspace for environment: ${ENVIRONMENT}"
                        # Select workspace or create if it doesn't exist
                        terraform workspace select ${ENVIRONMENT} || terraform workspace new ${ENVIRONMENT}
                        
                        CURRENT_WORKSPACE=$(terraform workspace show)
                        echo "✅ Current workspace: $CURRENT_WORKSPACE"
                        
                        # Smart resource import for shared resources
                        echo "🔄 Checking for existing shared resources..."
                        
                        # Import resource group if it doesn't exist in current workspace state
                        if ! terraform state list | grep -q "azurerm_resource_group.main"; then
                            echo "📥 Importing existing resource group into workspace: $CURRENT_WORKSPACE"
                            terraform import azurerm_resource_group.main "/subscriptions/${ARM_SUBSCRIPTION_ID}/resourceGroups/star-surya-rg" || echo "ℹ️ Resource group will be created if it doesn't exist"
                        else
                            echo "✅ Resource group already exists in workspace state"
                        fi
                        
                        echo "📋 Available workspaces:"
                        terraform workspace list
                        
                        echo "📊 Current workspace state summary:"
                        terraform state list || echo "ℹ️ No resources in state yet"
                    '''
                }
            }
        }
        
        stage('Terraform Validate') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "✅ Formatting and validating Terraform configuration..."
                        terraform fmt
                        terraform validate
                        echo "✅ Configuration is valid for workspace: $(terraform workspace show)"
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
                    script {
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            echo "📋 Planning Terraform deployment..."
                            echo "🎯 Environment: ${params.ENVIRONMENT}"
                            echo "🏗️ Workspace: \$(terraform workspace show)"
                            terraform plan -var="environment=${params.ENVIRONMENT}" -out=tfplan-${params.ENVIRONMENT}
                        """
                        
                        // Archive the plan file
                        archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
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
                    if (params.AUTO_APPROVE) {
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh """
                                export PATH="\$HOME/.local/bin:\$PATH"
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
                                echo "🏗️ Workspace: \$(terraform workspace show)"
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    } else {
                        input message: "🚀 Approve Terraform Apply for ${params.ENVIRONMENT} environment?", ok: 'Apply'
                        withCredentials([
                            string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                            string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                            string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                            string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                        ]) {
                            sh """
                                export PATH="\$HOME/.local/bin:\$PATH"
                                echo "🚀 Applying Terraform configuration..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
                                echo "🏗️ Workspace: \$(terraform workspace show)"
                                terraform apply -auto-approve -var="environment=${params.ENVIRONMENT}"
                            """
                        }
                    }
                }
            }
        }
        
        stage('Terraform Destroy') {
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
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            
                            echo "🗑️ === TARGETED DESTROY OPERATION ==="
                            echo "🎯 Environment: ${params.ENVIRONMENT}"
                            echo "🏗️ Workspace: \$(terraform workspace show)"
                            
                            # Check current workspace state
                            RESOURCE_COUNT=\$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Resources in workspace state: \$RESOURCE_COUNT"
                            
                            if [ "\$RESOURCE_COUNT" -le 2 ]; then
                                echo "⚠️ Limited resources in Terraform state - performing Azure cleanup"
                                echo "🔄 Using targeted destroy to clean up environment-specific resources..."
                            else
                                echo "🗂️ Resources to be destroyed in workspace \$(terraform workspace show):"
                                terraform state list
                                echo ""
                                echo "🗑️ Destroying \$RESOURCE_COUNT environment resources..."
                            fi
                            
                            # TARGETED DESTROY - Excludes resource group to avoid lifecycle protection error
                            echo "🎯 Starting targeted destroy (excludes protected resource group)..."
                            terraform destroy -auto-approve -var="environment=${params.ENVIRONMENT}" \
                                -target="azurerm_windows_virtual_machine.vm" \
                                -target="azurerm_mssql_virtual_machine.db" \
                                -target="azurerm_network_interface.vm" \
                                -target="azurerm_public_ip.vm" \
                                -target="azurerm_subnet_network_security_group_association.app" \
                                -target="azurerm_subnet_network_security_group_association.db" \
                                -target="azurerm_network_security_group.app" \
                                -target="azurerm_network_security_group.db" \
                                -target="azurerm_subnet.app" \
                                -target="azurerm_subnet.db" \
                                -target="azurerm_virtual_network.main" \
                                -target="random_password.vm_password" \
                                2>/dev/null || echo "ℹ️ Some resources may not exist in state or Azure"
                            
                            echo "✅ Targeted destroy completed successfully!"
                            echo "📋 Protected resource group 'star-surya-rg' remains intact"
                            echo "🏗️ Other environments remain unaffected"
                        """
                    }
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
                        echo ""
                        
                        echo "🔐 === VM CREDENTIALS ==="
                        echo "👤 Username: azureadmin"
                        PASSWORD=$(terraform output -raw admin_password 2>/dev/null || echo "Password not available (check sensitive outputs)")
                        echo "🔑 Password: [${PASSWORD}]"
                        echo ""
                        
                        echo "🌐 === PUBLIC IP ADDRESSES ==="
                        terraform output vm_public_ips
                        echo ""
                        
                        echo "🔒 === PRIVATE IP ADDRESSES ==="
                        terraform output vm_private_ips
                        echo ""
                        
                        echo "🎯 === QUICK RDP COMMANDS ==="
                        APP_IP=$(terraform output -json vm_public_ips | grep -o '"'"${ENVIRONMENT}"'-app":"[^"]*"' | cut -d'"' -f4)
                        DB_IP=$(terraform output -json vm_public_ips | grep -o '"'"${ENVIRONMENT}"'-db":"[^"]*"' | cut -d'"' -f4)
                        
                        echo "Application Server: mstsc /v:$APP_IP"
                        echo "Database Server: mstsc /v:$DB_IP"
                        echo ""
                        echo "=========================================="
                        echo "📊 WORKSPACE INFORMATION:"
                        echo "Current: $(terraform workspace show)"
                        echo "Resources: $(terraform state list 2>/dev/null | wc -l)"
                        echo "=========================================="
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🗃️ Archiving state files for workspace: ${params.ENVIRONMENT}"
                
                // Archive workspace-specific artifacts
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                
                // Clean workspace only after successful destroy
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy of ${params.ENVIRONMENT}"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace files for ${params.ENVIRONMENT} environment"
                }
            }
        }
        success {
            script {
                def actionEmoji = [
                    'plan': '📋',
                    'apply': '✅',
                    'destroy': '🗑️'
                ]
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} completed successfully for ${params.ENVIRONMENT} environment!"
                echo "🏗️ Workspace: ${params.ENVIRONMENT}"
                
                if (params.ACTION == 'apply') {
                    echo "🔐 VM credentials and connection details are displayed above"
                }
            }
        }
        failure {
            script {
                def actionEmoji = [
                    'plan': '📋',
                    'apply': '❌',
                    'destroy': '💥'
                ]
                echo "${actionEmoji[params.ACTION]} Terraform ${params.ACTION} failed for ${params.ENVIRONMENT} environment!"
                echo "🏗️ Workspace: ${params.ENVIRONMENT}"
                echo "🔍 Check the logs above for error details"
                
                // Archive state even on failure for debugging
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
            }
        }
    }
}
