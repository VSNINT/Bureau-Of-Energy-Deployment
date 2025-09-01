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
                        echo "ℹ️ No previous state files found (this is normal for first run)"
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
                        
                        # Show current workspace
                        CURRENT_WORKSPACE=$(terraform workspace show)
                        echo "✅ Current workspace: $CURRENT_WORKSPACE"
                        
                        # List all workspaces
                        echo "📋 Available workspaces:"
                        terraform workspace list
                    '''
                }
            }
        }
        
        stage('State Diagnostics') {
            steps {
                withCredentials([
                    string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                    string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                    string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                    string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                ]) {
                    sh '''
                        export PATH="$HOME/.local/bin:$PATH"
                        echo "🔍 === STATE DIAGNOSTICS ==="
                        echo "Environment: ${ENVIRONMENT}"
                        echo "Action: ${ACTION}"
                        echo "Workspace: $(terraform workspace show)"
                        echo "Working Directory: $(pwd)"
                        echo ""
                        
                        echo "📁 Files in current directory:"
                        ls -la
                        echo ""
                        
                        echo "📋 Terraform state status for workspace $(terraform workspace show):"
                        if [ -f "terraform.tfstate" ]; then
                            echo "✅ State file exists"
                            RESOURCE_COUNT=$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Resources in state: $RESOURCE_COUNT"
                            if [ "$RESOURCE_COUNT" -gt 0 ]; then
                                echo "🗂️ Resources:"
                                terraform state list
                            fi
                        else
                            echo "ℹ️ No state file found (normal for first deployment in this workspace)"
                        fi
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
                        echo "✅ Configuration is valid"
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
                            echo "📋 Planning Terraform deployment for workspace: \$(terraform workspace show)..."
                            echo "🎯 Environment: ${params.ENVIRONMENT}"
                            terraform plan -var="environment=${params.ENVIRONMENT}" -out=tfplan-${params.ENVIRONMENT}
                        """
                        
                        // Archive the plan file
                        archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true
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
                                echo "🚀 Applying Terraform configuration for workspace: \$(terraform workspace show)..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
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
                                echo "🚀 Applying Terraform configuration for workspace: \$(terraform workspace show)..."
                                echo "🎯 Environment: ${params.ENVIRONMENT}"
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
                    input message: "⚠️ Are you sure you want to DESTROY ${params.ENVIRONMENT} environment? This cannot be undone!", ok: 'Destroy'
                    withCredentials([
                        string(credentialsId: 'ARM_CLIENT_ID', variable: 'ARM_CLIENT_ID'),
                        string(credentialsId: 'ARM_CLIENT_SECRET', variable: 'ARM_CLIENT_SECRET'),
                        string(credentialsId: 'ARM_TENANT_ID', variable: 'ARM_TENANT_ID'),
                        string(credentialsId: 'ARM_SUBSCRIPTION_ID', variable: 'ARM_SUBSCRIPTION_ID')
                    ]) {
                        sh """
                            export PATH="\$HOME/.local/bin:\$PATH"
                            
                            echo "🗑️ === DESTROY OPERATION ==="
                            echo "🎯 Environment: ${params.ENVIRONMENT}"
                            echo "🏗️ Workspace: \$(terraform workspace show)"
                            
                            # Check current state
                            RESOURCE_COUNT=\$(terraform state list 2>/dev/null | wc -l)
                            echo "📊 Resources in workspace state: \$RESOURCE_COUNT"
                            
                            if [ "\$RESOURCE_COUNT" -eq 0 ]; then
                                echo "⚠️ No resources in Terraform state for this workspace!"
                                echo "✅ Nothing to destroy - workspace state is empty"
                            else
                                echo "🗂️ Resources to be destroyed:"
                                terraform state list
                                echo ""
                                echo "🗑️ Destroying \$RESOURCE_COUNT resources for ${params.ENVIRONMENT} environment..."
                                
                                # Try destroy with retries for NIC reservation issues
                                for i in {1..3}; do
                                    echo "🔄 Destroy attempt \$i of 3..."
                                    if terraform destroy -auto-approve -var="environment=${params.ENVIRONMENT}"; then
                                        echo "✅ Destroy completed successfully"
                                        break
                                    else
                                        if [ \$i -eq 3 ]; then
                                            echo "❌ All destroy attempts failed"
                                            exit 1
                                        else
                                            echo "⏳ Waiting 3 minutes before retry (NIC reservation timeout)..."
                                            sleep 180
                                        fi
                                    fi
                                done
                            fi
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
                        echo -n "🔑 Password: "
                        terraform output -raw admin_password 2>/dev/null || echo "Password not available (check sensitive outputs)"
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
                    '''
                }
            }
        }
    }
    
    post {
        always {
            script {
                echo "🗃️ Archiving state files for workspace: ${params.ENVIRONMENT}"
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
                archiveArtifacts artifacts: '.terraform.lock.hcl', fingerprint: true, allowEmptyArchive: true
                
                // Archive workspace-specific artifacts
                archiveArtifacts artifacts: "tfplan-${params.ENVIRONMENT}", fingerprint: true, allowEmptyArchive: true
                
                // Only clean workspace after successful destroy
                if (params.ACTION == 'destroy' && currentBuild.currentResult == 'SUCCESS') {
                    echo "🧹 Cleaning workspace after successful destroy of ${params.ENVIRONMENT}"
                    cleanWs()
                } else {
                    echo "📁 Preserving workspace to maintain state files for ${params.ENVIRONMENT}"
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
                echo "🔍 Check the logs above for error details"
                
                // Archive state even on failure to debug issues
                archiveArtifacts artifacts: 'terraform.tfstate*', fingerprint: true, allowEmptyArchive: true
            }
        }
    }
}
