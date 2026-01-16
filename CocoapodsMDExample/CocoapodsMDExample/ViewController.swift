//
//  ViewController.swift
//  CocoapodsMDExample
//
//  Created by 朱继超 on 12/17/25.
//

import UIKit
import MarkdownDisplayKit

class ViewController: UIViewController {

    private lazy var syncButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("Sync MarkdownView Demo", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openSyncDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var tableViewButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("TableView Streaming Demo", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openTableViewDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var crashReproButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle("TableView Crash Repro", for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 18, weight: .medium)
        button.addTarget(self, action: #selector(openCrashReproDemo), for: .touchUpInside)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        DispatchQueue.global().async {
            FontLoader.ensureFontsRegistered()
        }
        let titleLabel = UILabel()
        titleLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        titleLabel.text = "MarkdownDisplayKit Demo"
        titleLabel.backgroundColor = .systemBackground
        view.addSubview(titleLabel)
        view.addSubview(syncButton)
        view.addSubview(tableViewButton)
        view.addSubview(crashReproButton)
        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            titleLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            titleLabel.heightAnchor.constraint(equalToConstant: 44),

            syncButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            syncButton.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -60),

            tableViewButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            tableViewButton.topAnchor.constraint(equalTo: syncButton.bottomAnchor, constant: 20),

            crashReproButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            crashReproButton.topAnchor.constraint(equalTo: tableViewButton.bottomAnchor, constant: 20)

        ])
    }

    @objc private func openSyncDemo() {
        let vc = MarkdownExampleViewController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }
    
    @objc private func openTableViewDemo() {
        let vc = TableViewStreamingViewController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }

    @objc private func openCrashReproDemo() {
        let vc = CrashReproViewController()
        vc.modalPresentationStyle = .fullScreen
        self.present(vc, animated: true, completion: nil)
    }

}
